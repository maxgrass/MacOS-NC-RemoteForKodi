//
//   Copyright 2015 Sylvain Roux.
//
//   Licensed under the Apache License, Version 2.0 (the "License");
//   you may not use this file except in compliance with the License.
//   You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
//   Unless required by applicable law or agreed to in writing, software
//   distributed under the License is distributed on an "AS IS" BASIS,
//   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//   See the License for the specific language governing permissions and
//   limitations under the License.
//

#import "TodayViewController.h"
#import <NotificationCenter/NotificationCenter.h>


#define DEFAULT_ADDRESS @"192.168.0.101"
#define DEFAULT_PORT @"9090"


typedef NS_ENUM(NSInteger, KeyboardBehaviour) {
    textInput,
    command
};


@interface TodayViewController () <NCWidgetProviding, SRWebSocketDelegate> {
    NSString *p_hostAddress;
    NSString *p_port;
    BOOL p_scheduleUpdate;
    NSInteger p_playerid;
    double p_volumeLevel;
    KeyboardBehaviour p_keyboardBehaviour;
    NSMutableString *p_inputString;
    NSUInteger p_inputStringPos;
    NSUInteger p_inputStringLength;
    NSMutableArray *p_playlistItems;
    NSDate *p_lastPlaylistAdd;
    NSString *p_currentItemLabel;
    NSInteger p_currentItemPosition;
}

@property (readwrite) BOOL widgetAllowsEditing;

@end


@implementation TodayViewController

- (instancetype)init {
    if ( self = [super init] ) {
        [self fixDefaultsIfNeeded];
        self.widgetAllowsEditing = YES;
        p_scheduleUpdate = NO;
        p_keyboardBehaviour = command;
        p_playerid = -1;
        p_currentItemPosition = -1;
        p_lastPlaylistAdd = [NSDate date];
        p_playlistItems = [NSMutableArray array];
        [self loadSettings];
        [self loadControlState];
        self.preferredContentSize = CGSizeMake(0, 93);
    }
    return self;
}

- (void)widgetPerformUpdateWithCompletionHandler:(void (^)(NCUpdateResult result))completionHandler {
    // Update your data and prepare for a snapshot. Call completion handler when you are done
    // with NoData if nothing has changed or NewData if there is new data since the last
    // time we called you
    completionHandler(NCUpdateResultNoData);
}

- (void)fixDefaultsIfNeeded {
    //http://stackoverflow.com/questions/22242106/mac-sandbox-created-but-no-nsuserdefaults-plist
    NSArray *domains = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,NSUserDomainMask,YES);
    //File should be in library
    NSString *libraryPath = [domains firstObject];
    if (libraryPath) {
        NSString *preferensesPath = [libraryPath stringByAppendingPathComponent:@"Preferences"];
        
        //Defaults file name similar to bundle identifier
        NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        
        //Add correct extension
        NSString *defaultsName = [bundleIdentifier stringByAppendingString:@".plist"];
        NSString *defaultsPath = [preferensesPath stringByAppendingPathComponent:defaultsName];
        
        NSFileManager *manager = [NSFileManager defaultManager];
        
        if (![manager fileExistsAtPath:defaultsPath]) {
            //Create to fix issues
            [manager createFileAtPath:defaultsPath contents:nil attributes:nil];
            
            //And restart defaults at the end
            [NSUserDefaults resetStandardUserDefaults];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
    }
}

- (void)saveSettings {
    [self fixDefaultsIfNeeded];
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    [shared setObject:self.hostAddress.stringValue forKey:@"host"];
    [shared setObject:self.port.stringValue forKey:@"port"];
    [shared synchronize];
    p_hostAddress = self.hostAddress.stringValue;
    p_port = self.port.stringValue;
}

- (void)loadSettings {
    [self fixDefaultsIfNeeded];
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    if(p_hostAddress != nil) [self.hostAddress setStringValue:p_hostAddress];
    else {
        NSString *savedHostAddress = [shared objectForKey:@"host"];
        if(savedHostAddress != nil)[self.hostAddress setStringValue:savedHostAddress];
        else [self.hostAddress setStringValue:DEFAULT_ADDRESS];
    }
    if(p_port != nil) [self.port setStringValue:p_port];
    else {
        NSString *savedPortAddress = [shared objectForKey:@"port"];
        if(savedPortAddress != nil)[self.port setStringValue:savedPortAddress];
        else [self.port setStringValue:DEFAULT_PORT];
    }
}

- (void)saveControlState {
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    [shared setObject:[NSString stringWithFormat:@"%f", self.playerProgressBar.doubleValue] forKey:@"playerProgress"];
    [shared setObject:[NSString stringWithFormat:@"%f", self.volumeLevel.doubleValue] forKey:@"volume"];
//    [shared setObject:@(p_keyboardBehaviour) forKey:@"keyboardBehaviour"];
    [shared synchronize];
}

- (void)loadControlState {
//    NSString *d_keyboardBehaviour = [[NSUserDefaults standardUserDefaults] objectForKey:@"keyboardBehaviour"];
//    if(d_keyboardBehaviour != nil)
//        p_keyboardBehaviour = [d_keyboardBehaviour intValue];
}


/***** UI updates *****/

- (void)viewDidAppear {
    [self setEnabledPlayerControls:NO];
    [self connectToKodi];
    [self setEnabledInterface:NO];
}

- (void)viewDidDisappear {
    [self saveControlState];
    [p_socket close];
    p_scheduleUpdate = NO;
}

- (void)widgetDidBeginEditing {
    [p_socket close];
    [self.mainView setHidden:YES];
    [self setEnabledPlaylistControls:NO];
    [self.settingsView setHidden:NO];
    [self loadSettings];
    [self.view.window makeFirstResponder:self.hostAddress];
}

- (void)widgetDidEndEditing {
    [self saveSettings];
    [self.mainView setHidden:NO];
    if(p_playlistItems && [p_playlistItems count] > 1)
        [self setEnabledPlaylistControls:YES];
    [self.settingsView setHidden:YES];
    [self.view.window makeFirstResponder:self.view];
    [self connectToKodi];
}


/***** Network access *****/

- (void)connectToKodi {
    if(p_socket.readyState == 1) {
        [p_socket close];
    }
    
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    if(p_hostAddress == nil)
        p_hostAddress = [shared objectForKey:@"host"];
    if(p_hostAddress == nil)
        p_hostAddress = DEFAULT_ADDRESS;
    if(p_port == nil)
        p_port = [shared objectForKey:@"port"];
    if(p_port == nil)
        p_port = DEFAULT_PORT;
    
    NSString *stringUrl = [NSString stringWithFormat:@"ws://%@:%@/jsonrpc", p_hostAddress, p_port];
    
    p_socket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:stringUrl]]];
    p_socket.delegate = self;
    NSLog(@"Socket event : Atempting to connect to host at %@:%@", p_hostAddress, p_port);
    [p_socket open];
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    NSLog(@"Socket event : connected");
    [self setEnabledInterface:YES];
    [self requestPlayerGetActivePlayers:self];
    [self requestApplicationVolume:self];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"Socket error : %@", error.description);
    [self setEnabledInterface:NO];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason wasClean:(BOOL)wasClean {
    NSLog(@"Socket event : closed");
    [self setEnabledInterface:NO];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)data {
    NSError *parseError = nil;
    NSArray *message = [NSJSONSerialization
                             JSONObjectWithData:[data dataUsingEncoding:NSUTF8StringEncoding]
                             options:0
                             error:&parseError];
    if (!message)
        NSLog(@"JSON parsing error: %@", parseError);
    else {
        NSString *sRequestId = [message valueForKey:@"id"];
        
        //Responses to a request from Kodi
        if([sRequestId isNotEqualTo:[NSNull null]]) {
            int requestId = [sRequestId intValue];
            NSArray *result = [message valueForKey:@"result"];
            
            if([message valueForKey:@"error"]) {
                NSLog(@"Incoming message : %@", data);
                [self handleError];
            } else
                switch (requestId) {
                    case 0:
                        NSLog(@"Incoming message : %@", data);
                        break;
                    case 1:
                        [self handlePlayerGetPropertiesPercentageSpeed:result];
                        break;
                    case 2:
                        NSLog(@"Incoming message : %@", data);
                        [self handleApplicationVolume:result];
                        break;
                    case 3:
                        NSLog(@"Incoming message : %@", data);
                        [self handlePlaylistGetItems:result];
                        break;
                    case 4:
                        NSLog(@"Incoming message : %@", data);
                        [self handlePlayerGetItem:result];
                        break;
                    case 5:
                        [self handlePlayerGetActivePlayers:result];
                        break;
                    case 6:
                        NSLog(@"Incoming message : %@", data);
                        [self handlePlayerGetPropertiesPlaylistPosition:result];
                        break;
                    default:
                        break;
                }
        }
        //Notifications recieved from Kodi
        else {
            NSLog(@"Incoming message : %@", data);
            NSArray *method = [message valueForKey:@"method"];
            NSArray *params = [message valueForKey:@"params"];
            
            if([method isEqualTo:@"Player.OnPlay"]) {
                [self handlePlayerOnPlay:params];
            }
            else if([method isEqualTo:@"Player.OnPause"]) {
                [self handlePlayerOnPause];
            }
            else if([method isEqualTo:@"Player.OnStop"]) {
                [self handlePlayerOnStop:params];
            }
            else if([method isEqualTo:@"Input.OnInputRequested"]) {
                [self handleInputOnInputRequested:params];
            }
            else if([method isEqualTo:@"Input.OnInputFinished"]) {
                [self handleInputOnInputFinished];
            }
            else if([method isEqualTo:@"Playlist.OnClear"]) {
                [self handlePlaylistOnClear];
            }
            else if([method isEqualTo:@"Playlist.OnAdd"]) {
                [self handlePlaylistOnAdd:params];
            }
            else if([method isEqualTo:@"Application.OnVolumeChanged"]) {
                [self handleApplicationOnVolumeChanged:params];
            }
        }
    }
}

- (void)remoteRequest:(NSString *)request withLog:(BOOL)log {
    if(p_socket.readyState != 1) {
        [self connectToKodi];
    }
    else {
        if(log) NSLog(@"Sending request : %@", request);
        [p_socket send:request];
    }
}


/***** Kodi commands *****/

- (IBAction)sendInputDown:(id)sender {
    //Input.Down
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Down\"}"];
    [self remoteRequest:request withLog:YES];
    [self.godownButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.godownButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputLeft:(id)sender {
    //Input.Left
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Left\"}"];
    [self remoteRequest:request withLog:YES];
    [self.goleftButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.goleftButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputRight:(id)sender {
    //Input.Right
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Right\"}"];
    [self remoteRequest:request withLog:YES];
    [self.gorightButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.gorightButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputUp:(id)sender {
    //Input.Up
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Up\"}"];
    [self remoteRequest:request withLog:YES];
    [self.goupButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.goupButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputSelect:(id)sender {
    //Input.Select
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Select\"}"];
    [self remoteRequest:request withLog:YES];
    [self.selectButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.selectButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputExecuteActionBack:(id)sender {
    //Input.ExecuteAction back
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"back\"}}"];
    [self remoteRequest:request withLog:YES];
    [self.backButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.backButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputExecuteActionContextMenu:(id)sender {
    //Input.ExecuteAction contextmenu
    //Input.ShowOSD
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"contextmenu\"},\"id\":0}"];
    [self remoteRequest:request withLog:YES];
    request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ShowOSD\"}"];
    [self remoteRequest:request withLog:YES];
    [self.menuButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.menuButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputInfo:(id)sender {
    //Input.Info
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Info\"}"];
    [self remoteRequest:request withLog:YES];
    [self.infoButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.infoButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputHome:(id)sender {
    //Input.Home
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Home\"}"];
    [self remoteRequest:request withLog:YES];
    [self.homeButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.homeButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputExecuteActionPause:(id)sender {
    //Input.ExecuteAction pause
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"pause\"}}"];
    [self remoteRequest:request withLog:YES];
    [self.playButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.playButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputExecuteActionStop:(id)sender {
    //Input.ExecuteAction stop
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"stop\"}}"];
    [self remoteRequest:request withLog:YES];
    [self.stopButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.stopButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendApplicationSetVolume:(id)sender {
    //Application.SetVolume
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", self.volumeLevel.intValue];
    [self remoteRequest:request withLog:YES];
}

- (IBAction)sendApplicationSetVolumeIncrement:(id)sender {
    //Application.SetVolume p_volumeLevel+5
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", (int)p_volumeLevel+5];
    [self remoteRequest:request withLog:YES];
}

- (IBAction)sendApplicationSetVolumeDecrement:(id)sender {
    //Application.SetVolume p_volumeLevel-5
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", (int)p_volumeLevel-5];
    [self remoteRequest:request withLog:YES];
}

- (IBAction)sendPlayerSeek:(id)sender {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":%i}}", p_playerid, self.playerProgressBar.intValue];
    [self remoteRequest:request withLog:YES];
}

- (IBAction)sendPlayerSeekForward:(id)sender {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":\"smallforward\"}}", p_playerid];
    [self remoteRequest:request withLog:YES];
}

- (IBAction)sendPlayerSeekBackward:(id)sender {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":\"smallbackward\"}}", p_playerid];
    [self remoteRequest:request withLog:YES];
}

- (IBAction)sendPlayerSetSpeed:(id)sender {
    //Player.SetSpeed
    NSEvent *event = [[NSApplication sharedApplication] currentEvent];
    BOOL endingDrag = event.type == NSLeftMouseUp;
    
    int speed = 1;
    if(self.speedLevel.intValue != 0 && !endingDrag)
        speed = (int)pow(2,abs(self.speedLevel.intValue))*(self.speedLevel.intValue/abs(self.speedLevel.intValue));
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.SetSpeed\",\"params\":{\"playerid\":%ld,\"speed\":%i}}", p_playerid, speed];
    [self remoteRequest:request withLog:YES];
    
    if (endingDrag)
        [self.speedLevel setIntegerValue:0];
}

- (IBAction)sendPlayerGoToPrevious:(id)sender {
    //Player.GoTo
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":\"previous\"}}", p_playerid];
    [self remoteRequest:request withLog:YES];
    [self.nextPlaylistItemButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.nextPlaylistItemButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendPlayerGoToNext:(id)sender {
    //Player.GoTo
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":\"next\"}}", p_playerid];
    [self remoteRequest:request withLog:YES];
    [self.nextPlaylistItemButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.nextPlaylistItemButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendPlayerGoTo:(NSPopUpButton*)sender {
    //Player.GoTo
    if(p_currentItemPosition == [sender indexOfSelectedItem]) return;
    p_currentItemPosition = [sender indexOfSelectedItem];
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":%d}}", p_playerid, (int)p_currentItemPosition];
    [self remoteRequest:request withLog:YES];
    [self.nextPlaylistItemButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.nextPlaylistItemButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)sendInputSendText:(NSString *)string andSubmit:(BOOL)submit {
    //Input.SendText
    NSString *done;
    NSString *safeString = [string stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    if (submit) done = @"true";
    else done = @"false";
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.SendText\",\"params\":{\"text\":\"%@\",\"done\":%@}}", safeString, done];
    [self remoteRequest:request withLog:YES];
}

- (void)requestApplicationVolume:(id)sender {
    //Application.GetProperties
    NSString *request = [NSString stringWithFormat:@"{\"id\":2,\"jsonrpc\":\"2.0\",\"method\":\"Application.GetProperties\",\"params\":{\"properties\":[\"volume\"]}}"];
    [self remoteRequest:request withLog:YES];
}

- (void)requestPlayerGetPropertiesPercentageSpeed:(id)sender {
    //Player.GetProperties
    if (p_playerid == -1) return;
    NSString *request = [NSString stringWithFormat:@"{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetProperties\",\"params\":{\"playerid\":%ld,\"properties\":[\"percentage\",\"speed\"]}}", p_playerid];
    [self remoteRequest:request withLog:NO];
}

- (void)requestPlayerGetPropertiesPlaylistPosition {
    //Player.GetProperties
    if (p_playerid == -1) return;
    NSString *request = [NSString stringWithFormat:@"{\"id\":6,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetProperties\",\"params\":{\"playerid\":%ld,\"properties\":[\"position\"]}}", p_playerid];
    [self remoteRequest:request withLog:YES];
}

- (void)requestPlayerGetItem {
    //Player.GetItem
    NSString *request = [NSString stringWithFormat:@"{\"id\":4,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetItem\",\"params\":{\"playerid\":%ld}}", p_playerid];
    [self remoteRequest:request withLog:YES];
}

- (void)requestPlaylistGetItems:(id)sender {
    //Playlist.GetItems
    NSString *request = [NSString stringWithFormat:@"{\"id\":3,\"jsonrpc\":\"2.0\",\"method\":\"Playlist.GetItems\",\"params\":{\"playlistid\":%ld}}", p_playerid];
    [self remoteRequest:request withLog:YES];
}

- (void)requestPlayerGetActivePlayers:(id)sender {
    //Player.GetActivePlayers
    NSString *request = [NSString stringWithFormat:@"{\"id\":5,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetActivePlayers\"}"];
    [self remoteRequest:request withLog:NO];
}


/***** Handling functions to Kodi's messages *****/

- (void)handleError {
    [self handlePlayerOnStop:nil];
}

- (void)handleApplicationVolume:(NSArray*)params {
    //Response to Application.GetProperties
    p_volumeLevel = [[params valueForKey:@"volume"] doubleValue];
    [self.volumeLevel setDoubleValue:p_volumeLevel];
}

- (void)handlePlayerGetPropertiesPercentageSpeed:(NSArray*)params {
    //Response to Player.GetProperties Percentage Speed
    [self setEnabledPlayerControls:YES];
    
    //update progressbar
    [self.playerProgressBar setEnabled:YES];
    [self.playerProgressBar setDoubleValue:[[params valueForKey:@"percentage"] doubleValue]];
    
    if([[params valueForKey:@"speed"] integerValue] == 0)
        [self.playButton setImage:[NSImage imageNamed:@"play"]];
    else
        [self.playButton setImage:[NSImage imageNamed:@"pause"]];
}

- (void)handlePlaylistGetItems:(NSArray*)params {
    //Response to Playlist.GetItems
    p_playlistItems = [NSMutableArray arrayWithArray:[params valueForKey:@"items"]];
    
    if(p_playlistItems && [p_playlistItems count] > 1) {
        if(p_currentItemPosition == -1) p_currentItemPosition = 0;
        NSInteger itemPosition = 0;
        [self.playlistCombo removeAllItems];
        
        //populating playlist's interface nspopupbutton
        for(NSDictionary *playListItem in p_playlistItems) {
            itemPosition++;
            NSString *itemTitle = [playListItem valueForKey:@"label"];
            [self addItemToPlaylistView:itemTitle withPosition:itemPosition];
        }
        [self.playlistCombo selectItemAtIndex:p_currentItemPosition];
        [self setEnabledPlaylistControls:YES];
        [self requestPlayerGetItem];
    }
    else
        [self setEnabledPlaylistControls:NO];
}

- (void)handlePlayerGetItem:(NSArray*)params {
    //Response to Player.GetItem
    p_currentItemLabel = [[params valueForKey:@"item"] valueForKey:@"label"];
    
    if(p_currentItemPosition != -1)
        [self requestPlayerGetPropertiesPlaylistPosition];
}

- (void)handlePlayerGetPropertiesPlaylistPosition:(NSArray*)params {
    //Response to Player.GetProperties PlaylistPosition
    p_currentItemPosition = [[params valueForKey:@"position"] doubleValue];
    [self.playlistCombo selectItemAtIndex:p_currentItemPosition];
    if(p_currentItemLabel)
        [[self.playlistCombo selectedItem] setTitle:[NSString stringWithFormat:@"%02ld. %@", p_currentItemPosition+1, p_currentItemLabel]];
}

- (void)handlePlayerGetActivePlayers:(NSArray*)params {
    //Response to Player.GetItem
    if([params count] == 0) return;
    
    NSInteger oldPlayerId = p_playerid;
    p_playerid = [[[params firstObject] valueForKey:@"playerid"] integerValue];
    
    if(p_playerid != oldPlayerId)
        [self requestPlaylistGetItems:self];
    
    [self requestPlayerGetPropertiesPercentageSpeed:self];
    
    //schedule next update
    if(!p_scheduleUpdate) {
        p_scheduleUpdate = YES;
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                         target:self
                                       selector:@selector(handlePlayerGetActivePlayers_scheduled:)
                                       userInfo:nil
                                        repeats:NO];
    }
}

- (void)handlePlayerGetActivePlayers_scheduled:(NSTimer *)timer {
    if(!timer || !p_scheduleUpdate || p_socket.readyState != 1) return;
    p_scheduleUpdate = NO;
    [self requestPlayerGetActivePlayers:self];
}

- (void)handlePlayerOnPlay:(NSArray*)params {
    p_playerid = [[[[params valueForKey:@"data"] valueForKey:@"player"] valueForKey:@"playerid"] integerValue];
    p_currentItemLabel = [[[params valueForKey:@"data"] valueForKey:@"item"] valueForKey:@"title"];
    
    [self setEnabledPlayerControls:YES];
    
    if([p_playlistItems count] == 0) { //in case the player is open between onAdd and onPlay
        [p_playlistItems addObject:[[params valueForKey:@"data"] valueForKey:@"item"]];
        [self addItemToPlaylistView:p_currentItemLabel withPosition:1];
    }
    
    [self requestPlayerGetActivePlayers:self];
    
    if(!p_currentItemLabel || !p_playlistItems) //no current label = playlist titles missings
        [self requestPlaylistGetItems:self];
    else if(p_currentItemPosition != -1)
        [self requestPlayerGetPropertiesPlaylistPosition];
}

- (void)handlePlayerOnPause {
}

- (void)handlePlayerOnStop:(NSArray*)params {
    [self setEnabledPlayerControls:NO];
    p_currentItemLabel = nil;
    p_playerid = -1;
    p_scheduleUpdate = NO;
    if(!params || ![[[params valueForKey:@"data"] valueForKey:@"end"] boolValue]) {
        [self setEnabledPlaylistControls:NO];
        [self.playlistCombo removeAllItems];
        p_playlistItems = nil;
    }
}

- (void)handleInputOnInputRequested:(NSArray*)params {
    p_keyboardBehaviour = textInput;
    p_inputString = [NSMutableString stringWithString:[[params valueForKey:@"data"] valueForKey:@"value"]];
    p_inputStringPos = p_inputString.length;
    p_inputStringLength = p_inputString.length;
    [self.textView setHidden:NO];
    [self.playerView setHidden:YES];
}

- (void)handleInputOnInputFinished {
    p_keyboardBehaviour = command;
    [self.textView setHidden:YES];
    [self.playerView setHidden:NO];
}

- (void)handlePlaylistOnClear {
    [p_playlistItems removeAllObjects];
    p_currentItemPosition = -1;
    p_currentItemLabel = nil;
    p_playerid = -1;
}

- (void)handlePlaylistOnAdd:(NSArray*)params {
    if(p_currentItemPosition == -1) {
        p_currentItemPosition = 0;
    }
    
    p_playerid = [[[params valueForKey:@"data"] valueForKey:@"playlistid"] integerValue];
    
    NSDictionary *item = [[params valueForKey:@"data"] valueForKey:@"item"];
    NSString *itemTitle = [item valueForKey:@"title"];
    NSInteger itemPosition = [[[params valueForKey:@"data"] valueForKey:@"position"] integerValue];
    
    if(!p_playlistItems) p_playlistItems = [NSMutableArray array];
    [p_playlistItems addObject:item];
    if([p_playlistItems count] > 1)
        [self setEnabledPlaylistControls:YES];
    
    [self addItemToPlaylistView:itemTitle withPosition:itemPosition+1];
}

- (void)handleApplicationOnVolumeChanged:(NSArray*)params {
    p_volumeLevel = [[[params valueForKey:@"data"] valueForKey:@"volume"] doubleValue];
    [self.volumeLevel setIntegerValue:(NSInteger)p_volumeLevel];
}



/***** View helpers *****/

- (void)setEnabledInterface:(BOOL) enabled {
    if(!enabled) {
        [self.playerProgressBar setEnabled:NO];
        [self.playerProgressBar setDoubleValue:0.0];
        [self.speedLevel setEnabled:NO];
        [self.playButton setEnabled:NO];
        [self.stopButton setEnabled:NO];
        [self.forwardButton setEnabled:NO];
    }
    [self.godownButton setEnabled:enabled];
    [self.goleftButton setEnabled:enabled];
    [self.gorightButton setEnabled:enabled];
    [self.goupButton setEnabled:enabled];
    [self.selectButton setEnabled:enabled];
    [self.menuButton setEnabled:enabled];
    [self.infoButton setEnabled:enabled];
    [self.backButton setEnabled:enabled];
    [self.homeButton setEnabled:enabled];
    [self.volumeLevel setEnabled:enabled];
}

- (void)setEnabledPlayerControls:(BOOL) enabled {
    [self.playerProgressBar setEnabled:enabled];
    if(!enabled) [self.playerProgressBar setDoubleValue:0.0];
    [self.speedLevel setEnabled:enabled];
    [self.playButton setEnabled:enabled];
    [self.stopButton setEnabled:enabled];
    [self.forwardButton setEnabled:enabled];
}

- (void)setEnabledPlaylistControls:(BOOL) enabled {
    [self.nextPlaylistItemButton setEnabled:enabled];
    [self.playlistCombo setEnabled:enabled];
    if(enabled)
        self.preferredContentSize = CGSizeMake(0, 120);
    else
        self.preferredContentSize = CGSizeMake(0, 93);
}

- (void)addItemToPlaylistView:(NSString*) itemLabel withPosition:(NSInteger) itemPosition {
    
    if(!itemLabel || [itemLabel isEqualToString:@""]) {
        [self.playlistCombo addItemWithTitle:[NSString stringWithFormat:@"%02ld. missing item label", itemPosition]];
    } else {
        NSRange range = [itemLabel rangeOfString:@"[0-9]+\. .*" options:NSRegularExpressionSearch];
        if(range.location != NSNotFound)
            [self.playlistCombo addItemWithTitle:itemLabel];
        else
            [self.playlistCombo addItemWithTitle:[NSString stringWithFormat:@"%02ld. %@", itemPosition, itemLabel]];
    }
}


/***** Keyboard inputs *****/

- (void)keyDown:(NSEvent *)event {
//    NSLog(@"Key pressed : %u", event.keyCode);
    switch (p_keyboardBehaviour)
    {
        case textInput:
            [self keyboardAsTextInput:event];
            break;
        case command:
            [self keyboardCommandsMapping:event];
            break;
    }
}

- (void)keyboardAsTextInput:(NSEvent *)event {
    
    switch (event.keyCode)
    {
        case 36:  // return key
//            [self sendInputSendText:p_inputString.description andSubmit:YES];
            [self sendInputSelect:self];
            break;
        case 51:  // back key
            if (p_inputStringLength > 0) {
                if(p_inputStringPos < 1) break;
                NSString *postStr = [p_inputString substringFromIndex:p_inputStringPos];
                [p_inputString setString:[p_inputString substringToIndex:p_inputStringPos-1]];
                [p_inputString appendString:postStr];
                p_inputStringPos--;
                p_inputStringLength--;
                [self sendInputSendText:p_inputString.description andSubmit:NO];
                for (NSUInteger kodiCursorPos = p_inputStringLength; kodiCursorPos>p_inputStringPos; kodiCursorPos--) {
                    [self sendInputLeft:self];
                }
            } else {
                [self sendInputExecuteActionBack:self];
            }
            break;
        case 117:  // supr key
            if (p_inputStringPos < p_inputStringLength) {
                NSString *postStr = [p_inputString substringFromIndex:p_inputStringPos+1];
                [p_inputString setString:[p_inputString substringToIndex:p_inputStringPos]];
                [p_inputString appendString:postStr];
                p_inputStringLength--;
                [self sendInputSendText:p_inputString.description andSubmit:NO];
                for (NSUInteger kodiCursorPos = p_inputStringLength; kodiCursorPos>p_inputStringPos; kodiCursorPos--) {
                    [self sendInputLeft:self];
                }
            }
            break;
        case 123: // left key
//            if (p_inputStringPos > 0) {
//                p_inputStringPos--;
//                [self sendInputLeft:self];
//            }
            [self sendInputLeft:self];
            break;
        case 124: // right key
//            if (p_inputStringPos < p_inputStringLength) {
//                p_inputStringPos++;
//                [self sendInputRight:self];
//            }
            [self sendInputRight:self];
            break;
        case 125: // down key
            [self sendInputDown:self];
            break;
        case 126: // up key
            [self sendInputUp:self];
            break;
        case 9:
            if(event.modifierFlags & NSCommandKeyMask) {
                NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
                NSString* pastedString = [pasteboard  stringForType:NSPasteboardTypeString];
                if([pastedString containsString:@"\n"] || [pastedString containsString:@"\""]) break;
                NSString *postStr = [p_inputString substringFromIndex:p_inputStringPos];
                [p_inputString setString:[p_inputString substringToIndex:p_inputStringPos]];
                [p_inputString appendString:pastedString];
                [p_inputString appendString:postStr];
                p_inputStringPos+=pastedString.length;
                p_inputStringLength+=pastedString.length;
                [self sendInputSendText:p_inputString.description andSubmit:NO];
                for (NSUInteger kodiCursorPos = p_inputStringLength; kodiCursorPos>p_inputStringPos; kodiCursorPos--) {
                    [self sendInputLeft:self];
                }
                break;
            }
        default:
        {
            NSString *postStr = [p_inputString substringFromIndex:p_inputStringPos];
            [p_inputString setString:[p_inputString substringToIndex:p_inputStringPos]];
            [p_inputString appendString:event.characters];
            [p_inputString appendString:postStr];
            p_inputStringPos++;
            p_inputStringLength++;
            [self sendInputSendText:p_inputString.description andSubmit:NO];
            for (NSUInteger kodiCursorPos = p_inputStringLength; kodiCursorPos>p_inputStringPos; kodiCursorPos--) {
                [self sendInputLeft:self];
            }
            break;
        }
    }
}

- (void)keyboardCommandsMapping:(NSEvent *)event {
    switch (event.keyCode)
    {
        case 1: // s key
            [self sendInputExecuteActionStop:self];
            break;
        case 3: // b key
            [self sendPlayerSeekForward:self];
            break;
        case 11: // b key
            [self sendPlayerSeekBackward:self];
            break;
        case 4:  // h key
            [self sendInputHome:self];
            break;
        case 34:  // i key
            [self sendInputInfo:self];
            break;
        case 35:  // p key
            [self sendPlayerGoToPrevious:self];
            break;
        case 36:  // return key
            [self sendInputSelect:self];
            break;
        case 45:  // n key
            [self sendPlayerGoToNext:self];
            break;
        case 46:  // m key
            [self sendInputExecuteActionContextMenu:self];
            break;
        case 49:  // space key
            [self sendInputExecuteActionPause:self];
            break;
        case 51:  // back key
            [self sendInputExecuteActionBack:self];
            break;
        case 123: // left key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendPlayerSeekBackward:self];
            else
                [self sendInputLeft:self];
            break;
        case 124: // right key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendPlayerSeekForward:self];
            else
                [self sendInputRight:self];
            break;
        case 125: // down key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendApplicationSetVolumeDecrement:self];
            else
                [self sendInputDown:self];
            break;
        case 126: // up key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendApplicationSetVolumeIncrement:self];
            else
                [self sendInputUp:self];
            break;
        default:
            break;
    }
}

@end

