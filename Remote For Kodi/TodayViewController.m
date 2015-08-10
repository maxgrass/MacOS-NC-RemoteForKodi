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
    BOOL p_scheduleUpdatePlayerProgress;
    KeyboardBehaviour p_keyboardBehaviour;
    NSMutableString *p_inputString;
    NSUInteger p_inputStringPos;
    NSUInteger p_inputStringLength;
}

@property (readwrite) BOOL widgetAllowsEditing;

@end


@implementation TodayViewController

- (instancetype)init {
    if ( self = [super init] ) {
        self.widgetAllowsEditing = YES;
        p_scheduleUpdatePlayerProgress = NO;
        p_keyboardBehaviour = command;
        [self loadSettings];
        [self loadControlState];
        [self connectToKodi];
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
    [shared setObject:@(p_keyboardBehaviour) forKey:@"keyboardBehaviour"];
    [shared synchronize];
}

- (void)loadControlState {
    NSString *d_keyboardBehaviour = [[NSUserDefaults standardUserDefaults] objectForKey:@"keyboardBehaviour"];
    if(d_keyboardBehaviour != nil)
        p_keyboardBehaviour = [d_keyboardBehaviour intValue];
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
    [self getProperties:self];
    [self getVolume:self];
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
    NSDictionary *message = [NSJSONSerialization
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
            NSDictionary *result = [message valueForKey:@"result"];
            switch (requestId) {
                case 0:
                    break;
                case 1:
                    if ([result objectForKey:@"percentage"]) {
                        [self setEnabledPlayerControls:YES];
                        [self updatePlayerProgress:[[result valueForKey:@"percentage"] doubleValue]];
                        if([[result valueForKey:@"speed"] integerValue] == 1)
                            [self.playButton setImage:[NSImage imageNamed:@"pause"]];
                        else
                            [self.playButton setImage:[NSImage imageNamed:@"play"]];
                    }
                    else if ([result objectForKey:@"volume"]) {
                        [self.volumeLevel setDoubleValue:[[result valueForKey:@"volume"] doubleValue]];
                    }
                    else {
                        [self setEnabledPlayerControls:NO];
                        [self onPause];
                    }
                    break;
                default:
                    break;
            }
        }
        //Notifications recieved from Kodi
        else {
            NSDictionary *method = [message valueForKey:@"method"];
            if([method isEqualTo:@"Player.OnPlay"]) {
                [self onPlay];
            }
            else if([method isEqualTo:@"Player.OnPause"]) {
                [self onPause];
            }
            else if([method isEqualTo:@"Player.OnStop"]) {
                [self onStop];
            }
            else if([method isEqualTo:@"Input.OnInputRequested"]) {
                [self onInputRequested];
            }
            else if([method isEqualTo:@"Input.OnInputFinished"]) {
                [self onInputFinished];
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


/***** Kodi commands *****/

- (IBAction)goLeft:(id)sender {
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

- (IBAction)goRight:(id)sender {
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

- (IBAction)goUp:(id)sender {
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

- (IBAction)goDown:(id)sender {
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

- (IBAction)select:(id)sender {
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

- (IBAction)back:(id)sender {
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

- (IBAction)menu:(id)sender {
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

- (IBAction)info:(id)sender {
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

- (IBAction)home:(id)sender {
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

- (IBAction)pause:(id)sender {
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

- (IBAction)stop:(id)sender {
    //Input.ExecuteAction stop
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"stop\"},\"id\":0}"];
    [self remoteRequest:request];
}

- (IBAction)getProperties:(id)sender {
    //Player.GetProperties
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.GetProperties\",\"params\":{\"playerid\":1,\"properties\":[\"percentage\",\"speed\"]},\"id\":1}"];
    [self remoteRequest:request];
}

- (IBAction)getVolume:(id)sender {
    //Application.GetProperties
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Application.GetProperties\",\"params\":{\"properties\":[\"volume\"]},\"id\":1}"];
    [self remoteRequest:request];
}

- (IBAction)playerSeek:(id)sender {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":1,\"value\":%i},\"id\":1}", self.playerProgressBar.intValue];
    [self remoteRequest:request];
}

- (IBAction)setVolume:(id)sender {
    //Application.SetVolume
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i},\"id\":0}", self.volumeLevel.intValue];
    [self remoteRequest:request];
}

- (IBAction)setSpeed:(id)sender {
    //Player.SetSpeed
    NSEvent *event = [[NSApplication sharedApplication] currentEvent];
    BOOL endingDrag = event.type == NSLeftMouseUp;
    
    int speed = 1;
    if(self.speedLevel.intValue != 0 && !endingDrag)
        speed = (int)pow(2,abs(self.speedLevel.intValue))*(self.speedLevel.intValue/abs(self.speedLevel.intValue));
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.SetSpeed\",\"params\":{\"playerid\":1,\"speed\":%i},\"id\":0}", speed];
    [self remoteRequest:request];
    
    if (endingDrag)
        [self.speedLevel setIntegerValue:0];
}

- (IBAction)nextPlaylistItem:(id)sender {
    //Player.GoTo
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":1,\"to\":\"next\"},\"id\":0}"];
    [self remoteRequest:request];
}

- (IBAction)sendString:(NSString *)string andSubmit:(BOOL)submit {
    //Input.SendText
    NSString *done;
    if (submit) done = @"true";
    else done = @"false";
    NSString *request = [NSString stringWithFormat:@"{\"jsonrpc\":\"2.0\",\"method\":\"Input.SendText\",\"params\":{\"text\":\"%@\",\"done\":%@},\"id\":0}", string, done];
    [self remoteRequest:request];
}

/***** UI updates *****/

- (void)viewDidAppear {
    [self connectToKodi];
}

- (void)viewDidDisappear {
    [self saveControlState];
    [p_socket close];
    p_scheduleUpdatePlayerProgress = NO;
}

- (void)onPlay {
    [self setEnabledPlayerControls:YES];
    [self getProperties:self];
}

- (void)onPause {
}

- (void)onStop {
    [self setEnabledPlayerControls:NO];
}

- (void)onInputRequested {
    p_keyboardBehaviour = textInput;
    p_inputString = [[NSMutableString alloc] init];
    p_inputStringPos = 0;
    p_inputStringLength = 0;
    [self.goupButton setEnabled:NO];
    [self.godownButton setEnabled:NO];
    [self goUp:self]; //set focus on the input textfield
}

- (void)onInputFinished {
    [self.goupButton setEnabled:YES];
    [self.godownButton setEnabled:YES];
    p_keyboardBehaviour = command;
}

- (void)setEnabledPlayerControls:(BOOL) enabled {
    [self.playerProgressBar setEnabled:enabled];
    [self.playerProgressBar setDoubleValue:0.0];
    [self.speedLevel setEnabled:enabled];
    [self.playButton setEnabled:enabled];
    [self.stopButton setEnabled:enabled];
    [self.nextPlaylistItemButton setEnabled:enabled];
}

- (void)updatePlayerProgress:(double) percentage {
    [self.playerProgressBar setEnabled:YES];
    [self.playerProgressBar setDoubleValue:percentage];
    if(!p_scheduleUpdatePlayerProgress) {
        p_scheduleUpdatePlayerProgress = YES;
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                         target:self
                                       selector:@selector(scheduledPlayerProgressUpdate:)
                                       userInfo:nil
                                        repeats:NO];
    }
}

- (void)scheduledPlayerProgressUpdate:(NSTimer *)timer {
    if(!timer || !p_scheduleUpdatePlayerProgress) return;
    p_scheduleUpdatePlayerProgress = NO;
    [self getProperties:self];
}

//- (IBAction)displaySettings:(id)sender {
//    [self.mainView setHidden:YES];
//    [self.settingsView setHidden:NO];
//    [self.hostAddress setEnabled:YES];
//    [self.hostAddress setEditable:YES];
//    [self loadSettings];
//    [self.view.window makeFirstResponder:self.hostAddress];
//    p_keyboardBehaviour = settingsMapping;
//}
//
//- (IBAction)validateSettings:(id)sender {
//    [self saveSettings];
//    [self.mainView setHidden:NO];
//    [self.settingsView setHidden:YES];
//    [self.hostAddress setEnabled:NO];
//    [self.hostAddress setEditable:NO];
//    [self.view.window makeFirstResponder:self.view];
//    p_keyboardBehaviour = command;
//    [self connectToKodi];
//}

- (void)widgetDidBeginEditing {
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
                [self sendString:p_inputString.description andSubmit:NO];
                for (NSUInteger kodiCursorPos = p_inputStringLength; kodiCursorPos>p_inputStringPos; kodiCursorPos--) {
                    [self goLeft:self];
                }
            }
            break;
        case 47:
            break;
        case 36:  // return key
            [self sendString:p_inputString.description andSubmit:YES];
            break;
        case 51:  // back key
            if (p_inputStringPos > 0) {
                NSString *postStr = [p_inputString substringFromIndex:p_inputStringPos];
                [p_inputString setString:[p_inputString substringToIndex:p_inputStringPos-1]];
                [p_inputString appendString:postStr];
                p_inputStringPos--;
                p_inputStringLength--;
                [self sendString:p_inputString.description andSubmit:NO];
                for (NSUInteger kodiCursorPos = p_inputStringLength; kodiCursorPos>p_inputStringPos; kodiCursorPos--) {
                    [self goLeft:self];
                }
            } else {
                [self back:self];
            }
            break;
        case 117:  // supr key
            if (p_inputStringPos < p_inputStringLength) {
                NSString *postStr = [p_inputString substringFromIndex:p_inputStringPos+1];
                [p_inputString setString:[p_inputString substringToIndex:p_inputStringPos]];
                [p_inputString appendString:postStr];
                p_inputStringLength--;
                [self sendString:p_inputString.description andSubmit:NO];
                for (NSUInteger kodiCursorPos = p_inputStringLength; kodiCursorPos>p_inputStringPos; kodiCursorPos--) {
                    [self goLeft:self];
                }
            }
            break;
        case 123: // left key
            if (p_inputStringPos > 0) {
                p_inputStringPos--;
                [self goLeft:self];
            }
            break;
        case 124: // right key
            if (p_inputStringPos < p_inputStringLength) {
                p_inputStringPos++;
                [self goRight:self];
            }
            break;
        default:
        {
            NSString *postStr = [p_inputString substringFromIndex:p_inputStringPos];
            [p_inputString setString:[p_inputString substringToIndex:p_inputStringPos]];
            [p_inputString appendString:event.characters];
            [p_inputString appendString:postStr];
            p_inputStringPos++;
            p_inputStringLength++;
            [self sendString:p_inputString.description andSubmit:NO];
            for (NSUInteger kodiCursorPos = p_inputStringLength; kodiCursorPos>p_inputStringPos; kodiCursorPos--) {
                [self goLeft:self];
            }
            break;
        }
    }
}

- (void)keyboardCommandsMapping:(NSEvent *)event {
    switch (event.keyCode)
    {
        case 4:  // h key
            [self home:self];
            break;
        case 34:  // i key
            [self info:self];
            break;
        case 36:  // return key
            [self select:self];
            break;
        case 46:  // m key
            [self menu:self];
            break;
        case 49:  // space key
            [self pause:self];
            break;
        case 51:  // back key
            [self back:self];
            break;
        case 123: // left key
            [self goLeft:self];
            break;
        case 124: // right key
            [self goRight:self];
            break;
        case 125: // down key
            [self goDown:self];
            break;
        case 126: // up key
            [self goUp:self];
            break;
        default:
            break;
    }
}

@end

