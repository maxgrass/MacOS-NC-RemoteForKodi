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


#define DEFAULT_ADDRESS @"192.168.0.1"
#define DEFAULT_PORT @"9090"


typedef NS_ENUM(NSInteger, KeyboardBehaviour) {
    textInput,
    command
};


@interface TodayViewController () <NCWidgetProviding, SRWebSocketDelegate> {
    BOOL p_scheduleUpdate;
    NSInteger p_playerid;
    double p_volumeLevel;
    KeyboardBehaviour p_keyboardBehaviour;
    NSMutableString *p_inputString;
    NSUInteger p_inputStringPos;
    NSUInteger p_inputStringLength;
    NSDictionary *p_playlistItems;
    NSDate *p_lastPlaylistAdd;
    
    BOOL foo;
}

@property (readwrite) BOOL widgetAllowsEditing;

@end


@implementation TodayViewController

- (instancetype)init {
    if ( self = [super init] ) {
        self.widgetAllowsEditing = YES;
        p_scheduleUpdate = NO;
        p_keyboardBehaviour = command;
        p_playerid = -1;
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

- (void)saveSettings {
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    [shared setObject:self.hostAddress.stringValue forKey:@"host"];
    [shared setObject:self.port.stringValue forKey:@"port"];
    [shared synchronize];
}

- (void)loadSettings {
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    NSString *d_hostAddress = [shared objectForKey:@"host"];
    NSString *d_port = [shared objectForKey:@"port"];
    if(d_hostAddress != nil) [self.hostAddress setStringValue:d_hostAddress];
    else [self.hostAddress setStringValue:DEFAULT_ADDRESS];
    if(d_port != nil) [self.port setStringValue:d_port];
    else [self.port setStringValue:DEFAULT_PORT];
}

- (void)saveControlState {
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    [shared setObject:[NSString stringWithFormat:@"%f", self.playerProgressBar.doubleValue] forKey:@"playerProgress"];
    [shared setObject:[NSString stringWithFormat:@"%f", self.volumeLevel.doubleValue] forKey:@"volume"];
//    [shared setObject:@(p_keyboardBehaviour) forKey:@"keyboardBehaviour"];
    [shared synchronize];
}

- (void)loadControlState {
    NSString *d_keyboardBehaviour = [[NSUserDefaults standardUserDefaults] objectForKey:@"keyboardBehaviour"];
//    if(d_keyboardBehaviour != nil)
//        p_keyboardBehaviour = [d_keyboardBehaviour intValue];
}


/***** Network access *****/

- (void)connectToKodi {
    if(p_socket.readyState == 1) {
        [p_socket close];
    }
    
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    NSString *d_hostAddress = [shared objectForKey:@"host"];
    NSString *d_port = [shared objectForKey:@"port"];
    if(d_hostAddress == nil) {
        d_hostAddress = DEFAULT_ADDRESS;
        d_port = DEFAULT_PORT;
    }
    
    NSString *stringUrl = [NSString stringWithFormat:@"ws://%@:%@/jsonrpc", d_hostAddress, d_port];
    
    p_socket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:stringUrl]]];
    p_socket.delegate = self;
    NSLog(@"Socket event : Atempting to connect to host at %@:%@", d_hostAddress, d_port);
    [p_socket open];
    
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    NSLog(@"Socket event : connected");
    [self requestPlayerGetActivePlayers:self];
    [self requestApplicationVolume:self];
    [self requestPlayerGetActivePlayers:self];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"Socket error : %@", error.description);
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason wasClean:(BOOL)wasClean {
    NSLog(@"Socket event : closed");
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)data {
    NSLog(@"Input message : %@", data);
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
                [self handleError];
            } else
                switch (requestId) {
                    case 0:
                        break;
                    case 1:
                        [self handlePlayerGetProperties:result];
                        break;
                    case 2:
                        [self handleApplicationVolume:result];
                        break;
                    case 3:
                        [self handlePlaylistGetItems:result];
                        break;
                    case 4:
                        [self handlePlayerGetItem:result];
                        break;
                    case 5:
                        [self handlePlayerGetActivePlayers:result];
                        break;
                    default:
                        break;
                }
        }
        //Notifications recieved from Kodi
        else {
            NSArray *method = [message valueForKey:@"method"];
            NSArray *params = [message valueForKey:@"params"];
            if([method isEqualTo:@"Player.OnPlay"]) {
                [self handlePlayerOnPlay:params];
            }
            else if([method isEqualTo:@"Player.OnPause"]) {
                [self handlePlayerOnPause];
            }
            else if([method isEqualTo:@"Player.OnStop"]) {
                [self handlePlayerOnStop];
            }
            else if([method isEqualTo:@"Input.OnInputRequested"]) {
                [self handleInputOnInputRequested:params];
            }
            else if([method isEqualTo:@"Input.OnInputFinished"]) {
                [self handleInputOnInputFinished];
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

- (void)remoteRequest:(NSString *)request {
    if(p_socket.readyState != 1) {
        [self connectToKodi];
    }
    else {
        NSLog(@"Sending request : %@", request);
        [p_socket send:request];
    }
}


/***** UI updates *****/

- (void)viewDidAppear {
    [self setEnabledPlayerControls:NO];
    [self connectToKodi];
}

- (void)viewDidDisappear {
    [self saveControlState];
    [p_socket close];
    p_scheduleUpdate = NO;
}

- (void)widgetDidBeginEditing {
    [p_socket close];
    [self.mainView setHidden:YES];
    [self.settingsView setHidden:NO];
    [self loadSettings];
    [self.view.window makeFirstResponder:self.hostAddress];
}

- (void)widgetDidEndEditing {
    [self saveSettings];
    [self.mainView setHidden:NO];
    [self.settingsView setHidden:YES];
    [self.view.window makeFirstResponder:self.view];
    [self connectToKodi];
}


/***** Kodi commands *****/

- (IBAction)sendInputDown:(id)sender {
    //Input.Down
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.Down\",\"id\":0}"];
    [self remoteRequest:request];
    [self.godownButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.godownButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputLeft:(id)sender {
    //Input.Left
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.Left\",\"id\":0}"];
    [self remoteRequest:request];
    [self.goleftButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.goleftButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputRight:(id)sender {
    //Input.Right
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.Right\",\"id\":0}"];
    [self remoteRequest:request];
    [self.gorightButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.gorightButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputUp:(id)sender {
    //Input.Up
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.Up\",\"id\":0}"];
    [self remoteRequest:request];
    [self.goupButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.goupButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputSelect:(id)sender {
    //Input.Select
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.Select\",\"id\":0}"];
    [self remoteRequest:request];
    [self.selectButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.selectButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputExecuteActionBack:(id)sender {
    //Input.ExecuteAction back
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"back\"},\"id\":0}"];
    [self remoteRequest:request];
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
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"contextmenu\"},\"id\":0}"];
    [self remoteRequest:request];
    request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.ShowOSD\",\"id\":0}"];
    [self remoteRequest:request];
    [self.menuButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.menuButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputInfo:(id)sender {
    //Input.Info
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.Info\",\"id\":0}"];
    [self remoteRequest:request];
    [self.infoButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.infoButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputHome:(id)sender {
    //Input.Home
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.Home\",\"id\":0}"];
    [self remoteRequest:request];
    [self.homeButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.homeButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputExecuteActionPause:(id)sender {
    //Input.ExecuteAction pause
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"pause\"},\"id\":0}"];
    [self remoteRequest:request];
    [self.playButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.playButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputExecuteActionStop:(id)sender {
    //Input.ExecuteAction stop
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"stop\"},\"id\":0}"];
    [self remoteRequest:request];
}

- (IBAction)sendApplicationSetVolume:(id)sender {
    //Application.SetVolume
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i},\"id\":0}", self.volumeLevel.intValue];
    [self remoteRequest:request];
}

- (IBAction)sendApplicationSetVolumeIncrement:(id)sender {
    //Application.SetVolume p_volumeLevel+5
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i},\"id\":0}", (int)p_volumeLevel+5];
    [self remoteRequest:request];
}

- (IBAction)sendApplicationSetVolumeDecrement:(id)sender {
    //Application.SetVolume p_volumeLevel-5
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i},\"id\":0}", (int)p_volumeLevel-5];
    [self remoteRequest:request];
}

- (IBAction)sendPlayerSeek:(id)sender {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":%i},\"id\":0}", p_playerid, self.playerProgressBar.intValue];
    [self remoteRequest:request];
}

- (IBAction)sendPlayerSeekForward:(id)sender {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":\"smallforward\"},\"id\":0}", p_playerid];
    [self remoteRequest:request];
}

- (IBAction)sendPlayerSeekBackward:(id)sender {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":\"smallbackward\"},\"id\":0}", p_playerid];
    [self remoteRequest:request];
}

- (IBAction)sendPlayerSetSpeed:(id)sender {
    //Player.SetSpeed
    NSEvent *event = [[NSApplication sharedApplication] currentEvent];
    BOOL endingDrag = event.type == NSLeftMouseUp;
    
    int speed = 1;
    if(self.speedLevel.intValue != 0 && !endingDrag)
        speed = (int)pow(2,abs(self.speedLevel.intValue))*(self.speedLevel.intValue/abs(self.speedLevel.intValue));
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.SetSpeed\",\"params\":{\"playerid\":%ld,\"speed\":%i},\"id\":0}", p_playerid, speed];
    [self remoteRequest:request];
    
    if (endingDrag)
        [self.speedLevel setIntegerValue:0];
}

- (IBAction)sendPlayerGoToPrevious:(id)sender {
    //Player.GoTo
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":\"previous\"},\"id\":0}", p_playerid];
    [self remoteRequest:request];
}

- (IBAction)sendPlayerGoToNext:(id)sender {
    //Player.GoTo
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":\"next\"},\"id\":0}", p_playerid];
    [self remoteRequest:request];
    [self.nextPlaylistItemButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.nextPlaylistItemButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendPlayerGoTo:(id)sender {
    //Player.GoTo
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":%d},\"id\":0}", p_playerid, (int)[sender indexOfSelectedItem]];
    [self remoteRequest:request];
    [self.nextPlaylistItemButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.nextPlaylistItemButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)sendInputSendText:(NSString *)string andSubmit:(BOOL)submit {
    //Input.SendText
    NSString *done;
    NSString *safeString = [string stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    if (submit) done = @"true";
    else done = @"false";
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.SendText\",\"params\":{\"text\":\"%@\",\"done\":%@},\"id\":0}", safeString, done];
    [self remoteRequest:request];
}

- (IBAction)requestApplicationVolume:(id)sender {
    //Application.GetProperties
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Application.GetProperties\",\"params\":{\"properties\":[\"volume\"]},\"id\":2}"];
    [self remoteRequest:request];
}

- (IBAction)requestPlayerGetProperties:(id)sender {
    //Player.GetProperties
    if (p_playerid == -1) return;
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.GetProperties\",\"params\":{\"playerid\":%ld,\"properties\":[\"percentage\",\"speed\"]},\"id\":1}", p_playerid];
    [self remoteRequest:request];
}

- (IBAction)requestPlayerGetItem:(id)sender {
    //Player.GetItem
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.GetItem\",\"params\":{\"playerid\":%ld},\"id\":4}", p_playerid];
    [self remoteRequest:request];
}

- (IBAction)requestPlaylistGetItems:(id)sender {
    //Playlist.GetItems
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Playlist.GetItems\",\"params\":{\"playlistid\":%ld},\"id\":3}", p_playerid];
    [self remoteRequest:request];
}

- (IBAction)requestPlayerGetActivePlayers:(id)sender {
    //Player.GetActivePlayers
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.GetActivePlayers\",\"id\":5}"];
    [self remoteRequest:request];
}


/***** Handling functions to Kodi's messages *****/

- (void)handleError {
    [self handlePlayerOnStop];
}

- (void)handleApplicationVolume:(NSArray*)params {
    //Response to Application.GetProperties
    p_volumeLevel = [[params valueForKey:@"volume"] doubleValue];
    [self.volumeLevel setDoubleValue:p_volumeLevel];
}

- (void)handlePlayerGetProperties:(NSArray*)params {
    //Response to Player.GetProperties
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
    p_playlistItems = [params valueForKey:@"items"];
    [self requestPlayerGetItem:self];
}

- (void)handlePlayerGetItem:(NSArray*)params {
    //Response to Player.GetItem
    NSString *itemLabel;
    [self.playlistCombo removeAllItems];
    //item playing curently
    itemLabel = [[params valueForKey:@"item"] valueForKey:@"label"];
    if(p_playlistItems) {
        int currentItemId = 0;
        for (NSDictionary *playListItem in p_playlistItems) {
            currentItemId++;
            if([[playListItem valueForKey:@"label"] isEqualToString:@""])
                [self.playlistCombo addItemWithTitle:[NSString stringWithFormat:@"----- %d -----", currentItemId]];
            else
                [self.playlistCombo addItemWithTitle:[playListItem valueForKey:@"label"]];
        }
        
        currentItemId = 0;
        for(NSDictionary *playlistItem in p_playlistItems) {
            if([[playlistItem valueForKey:@"label"] rangeOfString:itemLabel].length)
                break;
            else if([[playlistItem valueForKey:@"label"] length] == 0)
                break;
            currentItemId++;
        }
        [self.playlistCombo selectItemAtIndex:currentItemId];
        
        if([p_playlistItems count] == 1)
            [self setEnabledPlaylistControls:NO];
        else
            [self setEnabledPlaylistControls:YES];
    }
    else
        [self setEnabledPlaylistControls:NO];

}

- (void)handlePlayerGetActivePlayers:(NSArray*)params {
    //Response to Player.GetItem
    if([params count] == 0) return;
    
    NSInteger oldPlayerId = p_playerid;
    p_playerid = [[[params firstObject] valueForKey:@"playerid"] integerValue];
    
    if(p_playerid != oldPlayerId)
        [self requestPlaylistGetItems:self];
    
    [self requestPlayerGetProperties:self];
    
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
    [self setEnabledPlayerControls:YES];
    [self requestPlayerGetActivePlayers:self];
    [self requestPlaylistGetItems:self];
}

- (void)handlePlayerOnPause {
}

- (void)handlePlayerOnStop {
    [self setEnabledPlayerControls:NO];
    p_playerid = -1;
    p_scheduleUpdate = NO;
    [NSTimer scheduledTimerWithTimeInterval:3.0
                                     target:self
                                   selector:@selector(handlePlayerOnStop_scheduled:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)handlePlayerOnStop_scheduled:(NSTimer *)timer {
    if(!timer) return;
    if(p_playerid == -1) {
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

- (void)handlePlaylistOnAdd:(NSArray*)params {
    //scheduled to handle multiple onAdd in a short delay without requesting the full playing for each.
    p_lastPlaylistAdd = [NSDate date];
    NSDate *now = [p_playlistItems copy];
    p_playerid = [[[params valueForKey:@"data"] valueForKey:@"playlistid"] integerValue];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self
                                   selector:@selector(handlePlaylistOnAdd_scheduled:)
                                   userInfo:now
                                    repeats:NO];
}

- (void)handlePlaylistOnAdd_scheduled:(NSTimer *)timer {
    if(!timer) return;
    if([p_lastPlaylistAdd isEqualToDate:(NSDate *)timer.userInfo])
        [self requestPlaylistGetItems:self];
}

- (void)handleApplicationOnVolumeChanged:(NSArray*)params {
    p_volumeLevel = [[[params valueForKey:@"data"] valueForKey:@"volume"] doubleValue];
    [self.volumeLevel setIntegerValue:(NSInteger)p_volumeLevel];
}



/***** View helpers *****/

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


/***** Keyboard inputs *****/

- (void)keyDown:(NSEvent *)event {
    NSLog(@"Key pressed : %u", event.keyCode);
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
        case 3: // f key
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

