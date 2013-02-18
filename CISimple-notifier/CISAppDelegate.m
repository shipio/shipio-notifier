//
//  PCAppDelegate.m
//  CISimple-notifier
//
//  Created by Romain Pouclet on 06/02/13.
//  Copyright (c) 2013 Perfectly Cooked. All rights reserved.
//

#import "CISAppDelegate.h"
#import "CISBuild.h"
#import "CISimple.h"
#import "SVHTTPRequest.h"
#import "NSUserNotification+Build.h"
#import "SSKeychain.h"
#import "NSHTTPError.h"
#import "CISProgressWindowController.h"

static NSString *kCISKeychainServiceName = @"cisimple";
static NSString *kCISKeychainTokenAccountName = @"token";
static NSString *kCISKeychainChannelAccountName = @"pusherChannel";

@implementation CISAppDelegate {
    CISimple *cisimple;
    BLYClient *bullyClient;
    BLYChannel *buildChannel;
    NSStatusItem *statusItem;

    CISProgressWindowController *progressWindowController;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Bootstrap used items
    progressWindowController = [[CISProgressWindowController alloc] init];
    [progressWindowController window];
    
    NSError *error = nil;
    NSString *apiKey = [SSKeychain passwordForService: kCISKeychainServiceName
                                                account: kCISKeychainTokenAccountName
                                                  error: &error];
    bullyClient = [[BLYClient alloc] initWithAppKey: @"01dfb12713a82c1e7088"
                                           delegate: self];
    
    NSLog(@"error code : %ld", (long)error.code);
    if (error != nil || apiKey == nil) {
        if ([error code] == errSecItemNotFound || apiKey == nil) {
            NSAlert *activateAlert = [NSAlert alertWithMessageText: @"API key required"
                                                     defaultButton: @"OK"
                                                   alternateButton: nil
                                                       otherButton: nil
                                         informativeTextWithFormat: @"It looks like this is your first time running the application. You'll need to enter your API Token to connect to cisimple."];

            [self presentPreferencesWindow];
            [activateAlert beginSheetModalForWindow: self.preferencesWindow
                                      modalDelegate: nil
                                     didEndSelector: nil
                                        contextInfo: nil];
        } else {
            [NSAlert alertWithError: error];
        }
    } else {
        self.apiTokenField.stringValue = apiKey;
        [self useApiToken: apiKey];
    }
}

- (void)connectToChannel:(NSString *)channel
{
    NSLog(@"Connecting to channel");
    
    buildChannel = [bullyClient subscribeToChannelWithName:channel authenticationBlock:^(BLYChannel *channel) {
        NSLog(@"Authenticate ?");
        [cisimple retrieveAuthentificationForParameters: channel.authenticationParameters
                                        completionBlock: ^(id response, NSError *error) {
                                            NSLog(@"Error %@", error.localizedDescription);
                                            [channel subscribeWithAuthentication: response];
                                        }];
    }];
    
    NSLog(@"Binding channel to build event");
    
    [buildChannel bindToEvent:kBuildUpdatedEventName block:^(id message) {
        NSLog(@"Received payload");
        CISBuild *build = [CISBuild buildWithDictionnary: message];
        NSLog(@"Build #%@, phase = %d", build.buildNumber, build.phase);
        
        if (build.phase == CISBuildPhaseCompleted) {
            NSLog(@"Phase is completed : ignoring");
            return;
        }
        
        NSUserNotification *n = [NSUserNotification notificationForBuild: build];
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification: n];
    }];
}

- (void)presentPreferencesWindow
{
    [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    [self.preferencesWindow makeKeyAndOrderFront: self];
}

- (void)didEnterAPIToken:(id)sender
{
    // Retrieve entered value
    NSString *apiKey = self.apiTokenField.stringValue;
    NSLog(@"Entered api key = %@", apiKey);
    
    [SSKeychain setPassword: apiKey
                 forService: kCISKeychainServiceName
                    account: kCISKeychainTokenAccountName];
    
    [self useApiToken: apiKey];
}

- (void)useApiToken:(NSString *)key
{
    if (nil != cisimple) {
        cisimple = nil;
    }
    
    if (nil != buildChannel) {
        buildChannel = nil;
    }
    
    cisimple = [[CISimple alloc] initWithToken: key delegate: self];
    
    NSError *error;
    NSString *channel = [SSKeychain passwordForService: kCISKeychainServiceName
                                               account: kCISKeychainChannelAccountName
                                                 error: &error];
    
    if (error.code == 0 && nil != channel) {
        NSLog(@"Channel name is = %@", channel);
        [self connectToChannel: channel];
    } else {
        [cisimple retrieveChannelInfo:^(id response, NSError *error) {
            if (nil == error) {
                NSLog(@"Channel name is = %@", response);
                [self connectToChannel: response];
                [SSKeychain setPassword: response forService: kCISKeychainServiceName account:kCISKeychainChannelAccountName];
            } else {
                NSLog(@"Got an error retrieving channel : %@", error.localizedDescription);
            
                NSAlert *errorAlert;
                // @todo better error handling ?
                if (error.code == 401) {
                    errorAlert = [NSAlert alertWithMessageText: @"Unable to connect"
                                                 defaultButton: @"Dismiss"
                                               alternateButton: nil
                                                   otherButton: nil
                                     informativeTextWithFormat: @"We were unable to connect to cisimple with the specified API token. Please verify you have entered it correctly."];
                } else {
                    errorAlert = [NSAlert alertWithMessageText: @"An error occured"
                                                 defaultButton: @"Dismiss"
                                               alternateButton: nil
                                                   otherButton: nil
                                     informativeTextWithFormat: @"An error occured when talking to cisimple. Try again later."];
                }
            
                [self presentPreferencesWindow];
                [errorAlert beginSheetModalForWindow: self.preferencesWindow
                                   modalDelegate: nil
                                  didEndSelector: nil
                                     contextInfo: nil];
            }
        }];
    }
}

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo;
{
    [sheet orderOut: self];
}

- (IBAction)didPressShowPreferencesWindow:(id)sender
{
    [self presentPreferencesWindow];
}

- (IBAction)didPressQuit:(id)sender
{
    NSLog(@"Terminate cisimple");
    [[NSApplication sharedApplication] terminate: nil];
}

- (void)awakeFromNib
{
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength: NSVariableStatusItemLength];
    statusItem.menu = self.statusBarMenu;
    statusItem.highlightMode = YES;
    statusItem.image = [NSImage imageNamed: @"icon_16x16"];
}

- (void)presentProgressView:(NSString *)message
{
    [self presentPreferencesWindow];
    [progressWindowController setMessage: message];
    
    [NSApp beginSheet: [progressWindowController window]
       modalForWindow: self.preferencesWindow
        modalDelegate: self
       didEndSelector: @selector(sheetDidEnd:returnCode:contextInfo:)
          contextInfo: nil];
}


- (IBAction)didPressGetAPIToken:(id)sender;
{
    NSLog(@"Opening cisimple");
    NSURL *cisimpleURL = [NSURL URLWithString: @"http://www.cisimple.com/account"];
    [[NSWorkspace sharedWorkspace] openURL: cisimpleURL];
}

#pragma mark cisimple
- (void)cisimpleClientFetchedChannel:(CISimple *)client channel:(NSString *)channel
{
    NSLog(@"Fetched channel : %@", channel);
    if (progressWindowController.window.isVisible) {
        NSLog(@"Progress window is visible -> removing progress view");
        [progressWindowController.window orderOut: self];
        [self.preferencesWindow orderOut: self];
    } else {
        NSLog(@"Progress window is not visible -> nothing to do");
    }

}

- (void)cisimpleClientStartedFetchingChannel:(CISimple *)client
{
    NSLog(@"Started fetching channel");
    if (self.preferencesWindow.isVisible) {
        NSLog(@"Preferences window is visible -> showing progress view");
        [self presentProgressView: @"Connecting to cisimple..."];
    } else {
        NSLog(@"Preferences window is not visible -> not showing progress view");
    }
}

#pragma mark bully

- (void)bullyClientDidConnect:(BLYClient *)client
{
    NSLog(@"Bully client did connect");
}

- (void)bullyClient:(BLYClient *)client didReceiveError:(NSError *)error
{
    NSLog(@"Bully client did receive error %@", error.localizedDescription);
}

- (void)bullyClientDidDisconnect:(BLYClient *)client
{
    NSLog(@"Bully client did disconnect");
}

@end
