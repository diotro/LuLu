//
//  file: Configure.m
//  project: lulu (config)
//  description: install/uninstall logic
//
//  created by Patrick Wardle
//  copyright (c) 2018 Objective-See. All rights reserved.
//

#import "consts.h"
#import "logging.h"
#import "Configure.h"
#import "utilities.h"

#import <IOKit/IOKitLib.h>
#import <Foundation/Foundation.h>
#import <Security/Authorization.h>
#import <ServiceManagement/ServiceManagement.h>

@implementation Configure

@synthesize gotHelp;
@synthesize xpcComms;

//invokes appropriate install || uninstall logic
-(BOOL)configure:(NSInteger)parameter
{
    //return var
    BOOL wasConfigured = NO;
    
    //uninstall flag
    BOOL uninstallFlag = UNINSTALL_FULL;
    
    //get help
    if(YES != [self initHelper])
    {
        //err msg
        syslog(LOG_ERR, "ERROR: failed to init helper tool");
        
        //bail
        goto bail;
    }
    
    //install
    if(ACTION_INSTALL_FLAG == parameter)
    {
        //dbg msg
        logMsg(LOG_DEBUG, @"installing...");
        
        //already installed?
        // perform an uninstall
        if(YES == [self isInstalled])
        {
            //dbg msg
            logMsg(LOG_DEBUG, @"already installed, so uninstalling...");
            
            //existing install, a beta?
            // set flag to perform full uninstall
            if(YES == [self isBetaInstalled])
            {
                //dbg msg
                logMsg(LOG_DEBUG, @"previous version is a beta, so will fully uninstall");
                
                //set flag
                uninstallFlag = UNINSTALL_FULL;
            }
            //non-beta
            // set flag to perform partial uninstall
            else
            {
                //dbg msg
                logMsg(LOG_DEBUG, @"previous version is not beta, so only partially uninstall");
                
                //set flag
                uninstallFlag = UNINSTALL_PARTIAL;
            }
            
            //uninstall
            if(YES != [self uninstall:uninstallFlag])
            {
                //bail
                goto bail;
            }
            
            //dbg msg
            logMsg(LOG_DEBUG, @"(partially) uninstalled");
        }
        
        //install
        if(YES != [self install])
        {
            //bail
            goto bail;
        }
        
        //dbg msg
        logMsg(LOG_DEBUG, @"installed!");
        
    }
    //uninstall
    else if(ACTION_UNINSTALL_FLAG == parameter)
    {
        //dbg msg
        logMsg(LOG_DEBUG, @"uninstalling...");
        
        //uninstall
        if(YES != [self uninstall:UNINSTALL_FULL])
        {
            //bail
            goto bail;
        }
        
        //dbg msg
        logMsg(LOG_DEBUG, @"uninstalled!");
    }

    //no errors
    wasConfigured = YES;
    
bail:
    
    return wasConfigured;
}

//determine if installed
// check if various firewall components are present
-(BOOL)isInstalled
{
    //flag
    BOOL installed = NO;
    
    //launch daemon
    NSString* launchDaemon = nil;
    
    //launch daemon plist
    NSString* launchDaemonPlist = nil;
    
    //app path
    NSString* appPath = nil;
    
    //init path to launch daemon
    launchDaemon = [INSTALL_DIRECTORY stringByAppendingPathComponent:LAUNCH_DAEMON_BINARY];
    
    //init path to launch daemon plist
    launchDaemonPlist = [@"/Library/LaunchDaemons" stringByAppendingPathComponent:LAUNCH_DAEMON_PLIST];
    
    //init path to app
    appPath = [@"/Applications" stringByAppendingPathComponent:APP_NAME];
    
    //check for installed components
    installed = ( (YES == [[NSFileManager defaultManager] fileExistsAtPath:KEXT]) ||
                  (YES == [[NSFileManager defaultManager] fileExistsAtPath:appPath]) ||
                  (YES == [[NSFileManager defaultManager] fileExistsAtPath:launchDaemon]) ||
                  (YES == [[NSFileManager defaultManager] fileExistsAtPath:launchDaemonPlist]) );
    
    return installed;
}

//determine if installed version is a beta
// just checks app bundle version, to see if it's starts w/ "0."
-(BOOL)isBetaInstalled
{
    //flag
    BOOL betaInstalled = NO;
    
    //app bundle
    NSBundle* appBundle = nil;
    
    //app version
    NSString* appVersion = nil;
    
    //dbg msg
    logMsg(LOG_DEBUG, @"checking if installed version is a beta...");
    
    //load app bundle
    appBundle = [NSBundle bundleWithPath:[@"/Applications" stringByAppendingPathComponent:APP_NAME]];
    if(nil == appBundle)
    {
        //bail
        goto bail;
    }
    
    //extract version
    appVersion = appBundle.infoDictionary[@"CFBundleVersion"];
    if(nil == appVersion)
    {
        //bail
        goto bail;
    }
    
    //dbg msg
    logMsg(LOG_DEBUG, [NSString stringWithFormat:@"existing (app) version: %@", appVersion]);
    
    //check for beta
    // version string that starts with "0."
    if(YES == [appVersion hasPrefix:@"0."])
    {
        //set flag
        betaInstalled = YES;
    }

bail:
    
    return betaInstalled;
}


//init helper tool
// install and establish XPC connection
-(BOOL)initHelper
{
    //bail if we're already G2G
    if(YES == self.gotHelp)
    {
        //all set
        goto bail;
    }
    
    //install
    if(YES != [self blessHelper])
    {
        //err msg
        syslog(LOG_ERR, "ERROR: failed to install helper tool");
        
        //bail
        goto bail;
    }
    
    //init XPC comms
    xpcComms = [[HelperComms alloc] init];
    if(nil == xpcComms)
    {
        //err msg
        syslog(LOG_ERR, "ERROR: failed to connect to helper tool");
        
        //bail
        goto bail;
    }
    
    //happy
    self.gotHelp = YES;
    
bail:
    
    return self.gotHelp;
}

//install helper tool
// sets 'wasBlessed' iVar
-(BOOL)blessHelper
{
    //flag
    BOOL wasBlessed = NO;
    
    //auth ref
    AuthorizationRef authRef = NULL;
    
    //error
    CFErrorRef error = NULL;
    
    //auth item
    AuthorizationItem authItem = {};
    
    //auth rights
    AuthorizationRights authRights = {};
    
    //auth flags
    AuthorizationFlags authFlags = 0;
    
    //create auth
    if(errAuthorizationSuccess != AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &authRef))
    {
        //err msg
        syslog(LOG_ERR, "ERROR: failed to create authorization");
        
        //bail
        goto bail;
    }
    
    //init auth item
    memset(&authItem, 0x0, sizeof(authItem));
    
    //set name
    authItem.name = kSMRightBlessPrivilegedHelper;
    
    //set auth count
    authRights.count = 1;
    
    //set auth items
    authRights.items = &authItem;
    
    //init flags
    authFlags =  kAuthorizationFlagDefaults | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagPreAuthorize | kAuthorizationFlagExtendRights;
    
    //get auth rights
    if(errAuthorizationSuccess != AuthorizationCopyRights(authRef, &authRights, kAuthorizationEmptyEnvironment, authFlags, NULL))
    {
        //err msg
        syslog(LOG_ERR, "ERROR: failed to copy authorization rights");
        
        //bail
        goto bail;
    }
    
    //bless
    if(YES != (BOOL)SMJobBless(kSMDomainSystemLaunchd, (__bridge CFStringRef)(CONFIG_HELPER_ID), authRef, &error))
    {
        //err msg
        syslog(LOG_ERR, "ERROR: failed to bless job (%s)", ((__bridge NSError*)error).description.UTF8String);
        
        //bail
        goto bail;
    }
    
    //happy
    wasBlessed = YES;
    
bail:
    
    //free auth ref
    if(NULL != authRef)
    {
        //free
        AuthorizationFree(authRef, kAuthorizationFlagDefaults);
        
        //unset
        authRef = NULL;
    }
    
    //free error
    if(NULL != error)
    {
        //release
        CFRelease(error);
        
        //unset
        error = NULL;
    }
    
    return wasBlessed;
}

//remove helper (daemon)
-(BOOL)removeHelper
{
    //return/status var
    __block BOOL wasRemoved = NO;
    
    //wait semaphore
    dispatch_semaphore_t semaphore = 0;
    
    //init sema
    semaphore = dispatch_semaphore_create(0);
    
    //if needed
    // tell helper to remove itself
    if(YES == self.gotHelp)
    {
        //cleanup
        [self.xpcComms cleanup:^(NSNumber *result)
        {
            //save result
            wasRemoved = (BOOL)(result.intValue == 0);
            
            //unset var
            if(YES == wasRemoved)
            {
                //unset
                self.gotHelp = NO;
            }
            
            //signal sema
            dispatch_semaphore_signal(semaphore);
            
        }];
        
        //wait for installer logic to be completed by XPC
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
    //didn't need to remove
    // just set ret var to 'ok'
    else
    {
        //set
        wasRemoved = YES;
    }
    
    return wasRemoved;
}

//install
-(BOOL)install
{
    //return/status var
    __block BOOL wasInstalled = NO;
    
    //wait semaphore
    dispatch_semaphore_t semaphore = 0;
    
    //path to login item
    NSString* loginItem = nil;
    
    //init sema
    semaphore = dispatch_semaphore_create(0);
    
    //define block
    void(^block)(NSNumber *) = ^(NSNumber *result)
    {
        //save result
        wasInstalled = (BOOL)(result.intValue == 0);
        
        //signal sema
        dispatch_semaphore_signal(semaphore);
    };
    
    //install
    // note, this is async
    [xpcComms install:block];
    
    //wait for installer logic to be completed by XPC
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    //dbg msg
    logMsg(LOG_DEBUG, [NSString stringWithFormat:@"privileged helper item install logic completed (%d)", wasInstalled]);
    
    //sanity check
    // make sure xpc install logic succeeded
    if(YES != wasInstalled)
    {
        //bail
        goto bail;
    }
    
    //init path to login item
    loginItem = [NSString pathWithComponents:@[@"/", @"Applications", APP_NAME, @"Contents", @"Library", @"LoginItems", [NSString stringWithFormat:@"%@.app", LOGIN_ITEM_NAME]]];
    
    //install login item
    // can't do this in script since it needs to be executed as logged in user (not r00t)
    if(YES != toggleLoginItem([NSURL fileURLWithPath:loginItem], ACTION_INSTALL_FLAG))
    {
        //err msg
        logMsg(LOG_ERR, @"failed to install login item");
        
        //set error
        wasInstalled = NO;
        
        //bail
        goto bail;
    }
    
    //dbg msg
    logMsg(LOG_DEBUG, [NSString stringWithFormat:@"installed login item (%@)", loginItem]);
    
    //happy
    wasInstalled = YES;
    
bail:
    
    return wasInstalled;
}

//uninstall
-(BOOL)uninstall:(BOOL)full
{
    //return/status var
    __block BOOL wasUninstalled = NO;
    
    //wait semaphore
    dispatch_semaphore_t semaphore = 0;
    
    //path to login item
    NSString* loginItem = nil;
    
    //init sema
    semaphore = dispatch_semaphore_create(0);
    
    //define block
    void (^block)(NSNumber *) = ^(NSNumber *result)
    {
        //save result
        wasUninstalled = (BOOL)(result.intValue == 0);
        
        //signal sema
        dispatch_semaphore_signal(semaphore);
    };
    
    //init path to login item
    loginItem = [NSString pathWithComponents:@[@"/", @"Applications", APP_NAME, @"Contents", @"Library", @"LoginItems", [NSString stringWithFormat:@"%@.app", LOGIN_ITEM_NAME]]];
    
    //uninstall login item, first
    // can't do this in script since it needs to be executed as logged in user (not r00t)
    if(YES != toggleLoginItem([NSURL fileURLWithPath:loginItem], ACTION_UNINSTALL_FLAG))
    {
        //err msg
        logMsg(LOG_ERR, @"failed to uninstall login item");
        
        //keep going though...
    }
    
    #ifdef DEBUG
    else
    {
        //dbg msg
        logMsg(LOG_DEBUG, [NSString stringWithFormat:@"uninstalled login item (%@)", loginItem]);
    }
    #endif
    
    //uninstall
    // also sets return/var flag
    [xpcComms uninstall:full reply:block];
    
    //wait for install to be completed by XPC
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    return wasUninstalled;
}

@end
