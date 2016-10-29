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

#define DEBUG_REQUEST_LOG
//#define DEBUG_HEARTBEAT_LOG

typedef NS_ENUM(NSInteger, KODI_PLAYER_ID);
typedef NS_ENUM(NSInteger, KEYBOARD_BEHAVIOR);
@interface KRPlaylistItem () {}
@end


@interface TodayViewController () <NCWidgetProviding, SRWebSocketDelegate, NSTextFieldDelegate> {
    
    /** Socket to kodi */
    SRWebSocket        *p_socket;
    /** //Kodi's address on the network */
    NSString           *p_hostAddress;
    /** Kodi's http port */
    NSString           *p_port;                             
    /** Kodi user's username */
    NSString           *p_username;                         
    /** Kodi user's password */
    NSString           *p_password;                         
    /** TRUE if an update of the player has been scheduled (in order to update the volume, player progress, etc ...) */
    BOOL                p_isHeartbeatOn;
    /** Curent kodi player's id */
    KODI_PLAYER_ID      p_playerID;
    /** Keyboard behavior in function of the current UI */
    KEYBOARD_BEHAVIOR   p_keyboardBehaviour;
    /** Date at the last add up in the current playlist */
    NSDate             *p_lastPlaylistAddDate;
    /** Date at the last request */
    NSDate             *p_lastRequestDate;                  
    /** String of the last request sent */
    NSString           *p_lastRequestString;
}

@property (readwrite) BOOL                              isInitiated;
@property (readwrite) BOOL                              isConected;
@property (readwrite) double                            playerItemCurrentTimePercentage;
@property (readwrite) KRPlayerItemTime                  playerItemCurrentTime;
@property (readwrite) KRPlayerItemTime                  playerItemTotalTime;
@property (readwrite) int                               playerSpeed;
@property (readwrite) double                            applicationVolume;
@property (readwrite) NSMutableArray                    *playlistItemsJson;
@property (readwrite) NSMutableArray<KRPlaylistItem*>   *playlistItems;
@property (readwrite) NSInteger                         currentItemPositionInPlaylist;
@property (readwrite) BOOL                              switchingItemInPlaylist;
@property (readwrite) BOOL                              isPlayerOn;
@property (readwrite) BOOL                              isPlaying;
@property (readwrite) BOOL                              isPlaylistOn;

@property (readwrite) BOOL widgetAllowsEditing;

@end



typedef NS_ENUM(NSInteger, KODI_PLAYER_ID) {
    NONE = -1,
    AUDIO = 0,
    VIDEO = 1
};

typedef NS_ENUM(NSInteger, KEYBOARD_BEHAVIOR) {
    TEXT_INPUT,
    COMMAND,
    SETTINGS
};

@implementation KRPlaylistItem

- (instancetype) initWithTitle:(NSString*) title {
    if ( self = [super init] ) {
        self.title = title;
    }
    return self;
}

@synthesize title = _title;

- (void)setTitle:(NSString *)title {
    @synchronized (self) {
        if(!_title)
            _title = @"";
        if(![title isEqualToString:@""])
            _title = title;
    }
}

- (NSString*)title {
    NSString *title = nil;
    @synchronized (self) {
        title = _title;
    }
    return title;
}

@end


@implementation TodayViewController


/***** Settings *****/

- (instancetype)init {
    if ( self = [super init] ) {
        [self fixDefaultsIfNeeded];
        self.switchingItemInPlaylist = NO;
        p_playerID = NONE;
        self.currentItemPositionInPlaylist = -1;
        p_lastPlaylistAddDate = [NSDate date];
        self.playlistItemsJson = [NSMutableArray array];
        self.playlistItems = [[NSMutableArray alloc] init];
        p_isHeartbeatOn = NO;
        [self loadSettings];
        [self loadControlState];
        
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(isInitiated))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(isConnected))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(playerItemCurrentTime))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(playerItemTotalTime))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(playerItemCurrentTimePercentage))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(playerSpeed))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(applicationVolume))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(playlistItems))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(currentItemPositionInPlaylist))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(switchingItemInPlaylist))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(isPlayerOn))
                  options:0
                  context:nil];
        [self addObserver:self
               forKeyPath:NSStringFromSelector(@selector(isPlaying))
                  options:0
                  context:nil];
        
        self.isInitiated = YES;
    }
    return self;
}

- (void)reset {
    if(p_socket.readyState == 1) {
        [p_socket close];
    }
    [self fixDefaultsIfNeeded];
    self.switchingItemInPlaylist = NO;
    p_playerID = NONE;
    self.currentItemPositionInPlaylist = -1;
    p_lastPlaylistAddDate = [NSDate date];
    self.playlistItemsJson = [NSMutableArray array];
    p_isHeartbeatOn = NO;
    [self loadSettings];
    [self loadControlState];
    [self connectToKodi];
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
    [shared setObject:self.xib_hostAddressTextField.stringValue forKey:@"host"];
    [shared setObject:self.xib_portTextField.stringValue forKey:@"port"];
    [shared setObject:self.xib_userTextField.stringValue forKey:@"username"];
    [shared setObject:self.xib_passwordTextField.stringValue forKey:@"password"];
    [shared synchronize];
    
    p_hostAddress = self.xib_hostAddressTextField.stringValue;
    p_port = self.xib_portTextField.stringValue;
    p_username = self.xib_userTextField.stringValue;
    p_password = self.xib_passwordTextField.stringValue;
}

- (void)loadSettings {
    [self fixDefaultsIfNeeded];
    [self.xib_versionTitle setStringValue:[NSString stringWithFormat:@"v. %@", @VERSION_NB]];
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    if(p_hostAddress != nil) [self.xib_hostAddressTextField setStringValue:p_hostAddress];
    else {
        NSString *savedHostAddress = [shared objectForKey:@"host"];
        if(savedHostAddress != nil)[self.xib_hostAddressTextField setStringValue:savedHostAddress];
        else [self.xib_hostAddressTextField setStringValue:@DEFAULT_ADDRESS];
    }
    if(p_port != nil) [self.xib_portTextField setStringValue:p_port];
    else {
        NSString *savedPortAddress = [shared objectForKey:@"port"];
        if(savedPortAddress != nil)[self.xib_portTextField setStringValue:savedPortAddress];
        else [self.xib_portTextField setStringValue:@DEFAULT_PORT];
    }
    if(p_username != nil) [self.xib_userTextField setStringValue:p_username];
    else {
        NSString *savedUsername = [shared objectForKey:@"username"];
        if(savedUsername != nil)[self.xib_userTextField setStringValue:savedUsername];
        else [self.xib_userTextField setStringValue:@DEFAULT_USERNAME];
    }
    if(p_password != nil) [self.xib_passwordTextField setStringValue:p_password];
    else {
        NSString *savedPassword = [shared objectForKey:@"password"];
        if(savedPassword != nil)[self.xib_passwordTextField setStringValue:savedPassword];
        else [self.xib_passwordTextField setStringValue:@DEFAULT_USERNAME];
    }
}

- (void)saveControlState {
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
//    [shared setObject:[NSString stringWithFormat:@"%f", self.playerProgressBar.doubleValue] forKey:@"playerProgress"];
//    [shared setObject:[NSString stringWithFormat:@"%f", self.volumeLevel.doubleValue] forKey:@"volume"];
//    [shared setObject:@(p_keyboardBehaviour) forKey:@"keyboardBehaviour"];
    [shared synchronize];
}

- (void)loadControlState {
//    NSString *d_keyboardBehaviour = [[NSUserDefaults standardUserDefaults] objectForKey:@"keyboardBehaviour"];
//    if(d_keyboardBehaviour != nil)
//        p_keyboardBehaviour = [d_keyboardBehaviour intValue];
}

- (void)setPlayerHeartbeat:(BOOL)status {
    if(status && p_isHeartbeatOn)
        return;
    p_isHeartbeatOn = status;
    [self playerHeartbeat];
}

- (void)playerHeartbeat {
    if(p_isHeartbeatOn) {
        [self requestPlayerGetPropertiesPercentageSpeed];
        [self requestPlayerGetActivePlayers];
        
        [NSTimer scheduledTimerWithTimeInterval:1.0
                                         target:self
                                       selector:@selector(playerHeartbeat)
                                       userInfo:nil
                                        repeats:NO];
    }
}


/***** UI updates *****/

- (void)viewDidAppear {
    [self ui_enablePlayerControls:NO];
    [self connectToKodi];
    [self ui_enableInterface:NO];
    if(p_hostAddress == nil)
       [self widgetDidBeginEditing];
}

- (void)viewDidDisappear {
    [self saveControlState];
    [p_socket close];
    [self setPlayerHeartbeat:NO];
}

- (void)widgetDidBeginEditing {
    [self setPlayerHeartbeat:NO];
    [p_socket close];
    [self.xib_mainView setHidden:YES];
    [self ui_showPlaylistControls:NO];
    
    p_keyboardBehaviour = SETTINGS;
    
    [self.xib_settingsView setHidden:NO];
    [self loadSettings];
    [self.view.window makeFirstResponder:self.xib_hostAddressTextField];
}

- (void)widgetDidEndEditing {
    [self saveSettings];
    
    p_keyboardBehaviour = COMMAND;
    
    [self.xib_mainView setHidden:NO];
    [self.xib_settingsView setHidden:YES];
    [self.view.window makeFirstResponder:self.view];
    [self reset];
//    [self connectToKodi];
//    [self setPlayerHeartbeat:YES];
}

- (void)widgetPerformUpdateWithCompletionHandler:(void (^)(NCUpdateResult result))completionHandler {
    // Update your data and prepare for a snapshot. Call completion handler when you are done
    // with NoData if nothing has changed or NewData if there is new data since the last
    // time we called you
    completionHandler(NCUpdateResultNoData);
}


/***** Network access *****/

- (void)connectToKodi {
    if(p_socket.readyState == 1) {
        [p_socket close];
    }
    
    NSUserDefaults *shared = [NSUserDefaults standardUserDefaults];
    
    if(p_hostAddress == nil) {
        p_hostAddress = [shared objectForKey:@"host"];
        if(p_hostAddress == nil)
            p_hostAddress = @DEFAULT_ADDRESS;
    }
    if(p_port == nil) {
        p_port = [shared objectForKey:@"port"];
        if(p_port == nil)
            p_port = @DEFAULT_PORT;
    }
    if(p_username == nil) {
        p_username = [shared objectForKey:@"username"];
        if(p_username == nil)
            p_username = @DEFAULT_USERNAME;
    }
    if(p_password == nil) {
        p_password = [shared objectForKey:@"password"];
        if(p_password == nil)
            p_password = @DEFAULT_PASSWORD;
    }
    
    NSString *stringURL;
    if([p_username isEqualToString:@""])
        stringURL = [NSString stringWithFormat:@"ws://%@:%@/jsonrpc", p_hostAddress, p_port];
    else
        stringURL = [NSString stringWithFormat:@"ws://%@:%@@%@:%@/jsonrpc", p_username, p_password, p_hostAddress, p_port];
    
    
    p_socket = [[SRWebSocket alloc] initWithURLRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:stringURL]]];
    p_socket.delegate = self;
    NSLog(@"Socket event : Atempting to connect to host at %@:%@", p_hostAddress, p_port);
    [p_socket open];
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket {
    NSLog(@"Socket event : connected");
    [self setPlayerHeartbeat:YES];
    [self requestApplicationVolume];
    self.isConnected = YES;
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error {
    NSLog(@"Socket error : %@", error.description);
    [self ui_enableInterface:NO];
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code
           reason:(NSString *)reason wasClean:(BOOL)wasClean {
    NSLog(@"Socket event : closed");
    self.isConnected = NO;
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
        
        //Responses to a request earlier sent to Kodi
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
#ifdef DEBUG_HEARTBEAT_LOG
                        NSLog(@"Incoming message : %@", data);
#endif
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
#ifdef DEBUG_HEARTBEAT_LOG
                        NSLog(@"Incoming message : %@", data);
#endif
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
            else if([method isEqualTo:@"GUI.OnScreensaverDeactivated"]) {
                [self handleGUIOnScreenSaverDeactivated];
            }
        }
    }
}

- (void)remoteRequest:(NSString *)request{
    if(p_socket.readyState == SR_CLOSED) {
        [self connectToKodi];
    }
    else if(p_socket.readyState == SR_OPEN) {
        p_lastRequestDate = [NSDate date];
        p_lastRequestString = [NSString stringWithString:request];
        [p_socket send:request];
    }
}


/***** Kodi commands *****/

- (void)sendInputDown {
    //Input.Down
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Down\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputLeft {
    //Input.Left
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Left\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputRight {
    //Input.Right
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Right\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputUp {
    //Input.Up
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Up\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputSelect {
    //Input.Select
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Select\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputExecuteActionBack {
    //Input.ExecuteAction back
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"back\"}}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputExecuteActionContextMenu {
    //Input.ExecuteAction contextmenu
    //Input.ShowOSD
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"contextmenu\"},\"id\":0}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
    request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ShowOSD\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputInfo {
    //Input.Info
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Info\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputHome {
    //Input.Home
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.Home\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputExecuteActionPause {
    //Input.ExecuteAction pause
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"pause\"}}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputExecuteActionStop {
    //Input.ExecuteAction stop
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.ExecuteAction\",\"params\":{\"action\":\"stop\"}}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendApplicationSetVolume:(int)volume {
    //Application.SetVolume
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", volume];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendApplicationSetVolumeIncrement {
    //Application.SetVolume applicationVolume+5
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", (int)self.applicationVolume+5];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendApplicationSetVolumeDecrement {
    //Application.SetVolume self.applicationVolume-5
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Application.SetVolume\",\"params\":{\"volume\":%i}}", (int)self.applicationVolume-5];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlayerOpenVideo {
    //Player.Open
    NSString *request = @"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Open\",\"params\":{\"item\":{\"playlistid\":1}}}";
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlaylistAddVideoStreamLink:(NSString *)link {
    //Playlist.Add
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Playlist.Add\",\"params\":{\"playlistid\":1, \"item\":{\"file\":\"%@\"}}}", link];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlaylistClearVideo {
    //Playlist.Clear
    NSString *request = @"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Playlist.Clear\",\"params\":{\"playlistid\":1}}";
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlayerSeek:(int)percentage {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":%i}}", p_playerID, percentage];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlayerSeekForward {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":\"smallforward\"}}", p_playerID];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlayerSeekBackward {
    //Player.Seek
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.Seek\",\"params\":{\"playerid\":%ld,\"value\":\"smallbackward\"}}", p_playerID];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlayerMarkAsWatched {
    [self sendInputExecuteActionContextMenu];
    for (int i = 0; i<4; i++) {
        [self sendInputDown];
    }
    [self sendInputSelect];
}

- (void)sendPlayerSetSpeed:(int)speed {
    //Player.SetSpeed
    int lc_speed;
    if(speed == 0)
        lc_speed = 0;
    else
        lc_speed = (int)pow(2,abs(speed))*(speed/abs(speed)); //[1]=2 [2]=4 [3]=8 [4]=16 [5]=32
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.SetSpeed\",\"params\":{\"playerid\":%ld,\"speed\":%i}}", p_playerID, lc_speed];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlayerGoToPrevious {
    //Player.GoTo
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":\"previous\"}}", p_playerID];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlayerGoToNext {
    //Player.GoTo
    if(self.switchingItemInPlaylist) return;
    self.switchingItemInPlaylist = YES;
    self.currentItemPositionInPlaylist++;
    
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":\"next\"}}", p_playerID];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendPlayerGoTo:(int)playlistItemId {
    //Player.GoTo
    if(self.switchingItemInPlaylist) return;
    self.switchingItemInPlaylist = YES;
    if(self.currentItemPositionInPlaylist == playlistItemId) {
        self.switchingItemInPlaylist = NO;
        return;
    }
    self.currentItemPositionInPlaylist = playlistItemId;
    
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Player.GoTo\",\"params\":{\"playerid\":%ld,\"to\":%d}}", p_playerID, (int)self.currentItemPositionInPlaylist];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendSystemReboot {
    //System.Reboot
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"System.Reboot\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendVideoLibraryScan {
    //VideoLibrary.Scan
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"VideoLibrary.Scan\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)sendInputSendText:(NSString *)string andSubmit:(BOOL)submit {
    //Input.SendText
    NSString *done;
    NSString *safeString = [string stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    if (submit) done = @"true";
    else done = @"false";
    NSString *request = [NSString stringWithFormat:@"{\"id\":0,\"jsonrpc\":\"2.0\",\"method\":\"Input.SendText\",\"params\":{\"text\":\"%@\",\"done\":%@}}", safeString, done];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)requestApplicationVolume {
    //Application.GetProperties
    NSString *request = [NSString stringWithFormat:@"{\"id\":2,\"jsonrpc\":\"2.0\",\"method\":\"Application.GetProperties\",\"params\":{\"properties\":[\"volume\"]}}"];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)requestPlayerGetPropertiesPercentageSpeed {
    //Player.GetProperties
    if (p_playerID == NONE) return;
    NSString *request = [NSString stringWithFormat:@"{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetProperties\",\"params\":{\"playerid\":%ld,\"properties\":[\"time\",\"totaltime\",\"percentage\",\"speed\"]}}", p_playerID];
    [self remoteRequest:request];
#ifdef DEBUG_HEARTBEAT_LOG
    NSLog(@"%@",request);
#endif
}

- (void)requestPlayerGetPropertiesPlaylistPosition {
    //Player.GetProperties
    if (p_playerID == -1) return;
    NSString *request = [NSString stringWithFormat:@"{\"id\":6,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetProperties\",\"params\":{\"playerid\":%ld,\"properties\":[\"position\"]}}", p_playerID];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)requestPlayerGetItem {
    //Player.GetItem
    NSString *request = [NSString stringWithFormat:@"{\"id\":4,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetItem\",\"params\":{\"playerid\":%ld}}", p_playerID];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)requestPlaylistGetItems {
    //Playlist.GetItems
    NSString *request = [NSString stringWithFormat:@"{\"id\":3,\"jsonrpc\":\"2.0\",\"method\":\"Playlist.GetItems\",\"params\":{\"playlistid\":%ld}}", p_playerID];
    [self remoteRequest:request];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",request);
#endif
}

- (void)requestPlayerGetActivePlayers {
    //Player.GetActivePlayers
    NSString *request = [NSString stringWithFormat:@"{\"id\":5,\"jsonrpc\":\"2.0\",\"method\":\"Player.GetActivePlayers\"}"];
    [self remoteRequest:request];
#ifdef DEBUG_HEARTBEAT_LOG
    NSLog(@"%@",request);
#endif
}

- (void)requestLastRequest {
    [self remoteRequest:p_lastRequestString];
#ifdef DEBUG_REQUEST_LOG
    NSLog(@"%@",p_lastRequestString);
#endif
}


/***** Handling functions to Kodi's messages *****/

- (void)handleError {
//    [self handlePlayerOnStop:nil];
}

- (void)handleApplicationVolume:(NSArray*)params {
    //Response to Application.GetProperties
    self.applicationVolume = [[params valueForKey:@"volume"] doubleValue];
}

- (void)handlePlayerGetPropertiesPercentageSpeed:(NSArray*)params {
    //Response to Player.GetProperties Percentage Speed
    NSArray *time = [params valueForKey:@"time"];
    NSArray *totalTime = [params valueForKey:@"totaltime"];
    
    KRPlayerItemTime localPlayerItemCurrentTime;
    localPlayerItemCurrentTime.hours    = [[time valueForKey:@"hours"] longValue];
    localPlayerItemCurrentTime.minutes  = [[time valueForKey:@"minutes"] longValue];
    localPlayerItemCurrentTime.seconds  = [[time valueForKey:@"seconds"] longValue];
    
    KRPlayerItemTime localPlayerItemTotalTime;
    localPlayerItemTotalTime.hours      = [[totalTime valueForKey:@"hours"] longValue];
    localPlayerItemTotalTime.minutes    = [[totalTime valueForKey:@"minutes"] longValue];
    localPlayerItemTotalTime.seconds    = [[totalTime valueForKey:@"seconds"] longValue];
    
    self.playerItemCurrentTime = localPlayerItemCurrentTime;
    if(localPlayerItemTotalTime.hours != self.playerItemTotalTime.hours ||
       localPlayerItemTotalTime.minutes != self.playerItemTotalTime.minutes ||
       localPlayerItemTotalTime.seconds != self.playerItemTotalTime.seconds)
        self.playerItemTotalTime = localPlayerItemTotalTime;
    self.playerItemCurrentTimePercentage = [[params valueForKey:@"percentage"] doubleValue];
    self.playerSpeed = [[params valueForKey:@"speed"] intValue];
}

- (void)handleInputOnInputRequested:(NSArray*)params {
    
    //UI update
    p_keyboardBehaviour = TEXT_INPUT;
    [self ui_enableNavigationControls:NO];
    [self.xib_textView setHidden:NO];
    [self.view.window makeFirstResponder:self.xib_inputTextToKodiTextField];
    [self.xib_playerView setHidden:YES];
}

- (void)handleInputOnInputFinished {
    
    //UI update
    p_keyboardBehaviour = COMMAND;
    [self ui_enableNavigationControls:YES];
    [self.view.window makeFirstResponder:self.view];
    [self.xib_textView setHidden:YES];
    [self.xib_playerView setHidden:NO];
}

- (void)handleApplicationOnVolumeChanged:(NSArray*)params {
    self.applicationVolume = [[[params valueForKey:@"data"] valueForKey:@"volume"] doubleValue];
}

- (void)handleGUIOnScreenSaverDeactivated {
    if (p_lastRequestDate && [[NSDate date] timeIntervalSinceDate:p_lastRequestDate] < 2
        && ![p_lastRequestString containsString:@"Player.Open"]
        && ![p_lastRequestString containsString:@"Playlist.Add"]) {
        [self requestLastRequest];
    }
}

- (void)handlePlayerGetPropertiesPlaylistPosition:(NSArray*)params {
    self.currentItemPositionInPlaylist = [[params valueForKey:@"position"] doubleValue];
    [self requestPlayerGetItem];
}

- (void)handlePlayerGetItem:(NSArray*)params {
    NSString * itemLabel = [[params valueForKey:@"item"] valueForKey:@"label"];
    [self setTitle:itemLabel forItemAtIndex:self.currentItemPositionInPlaylist];
    self.playlistItems = self.playlistItems;
}

- (void)handlePlayerGetActivePlayers:(NSArray*)params {
    //Stop heartbeat if no active players
    if([params count] == 0) {
        [self setPlayerHeartbeat:NO];
        p_playerID = NONE;
        self.isPlayerOn = NO;
    }
    else {
        NSInteger oldPlayerID = p_playerID;
        p_playerID = [[[params firstObject] valueForKey:@"playerid"] integerValue];
        self.isPlayerOn = YES;
        if(p_playerID != oldPlayerID) {
            [self requestPlaylistGetItems];
        }
    }
}

- (void)handlePlayerOnPlay:(NSArray*)params {
    self.isPlayerOn = YES;
    self.isPlaying = YES;
    self.switchingItemInPlaylist = NO;
    
    //Keep heartbeat on when something is playing
    [self setPlayerHeartbeat:YES];
    [self requestPlayerGetItem];
}

- (void)handlePlayerOnPause {
    self.isPlaying = NO;
}

- (void)handlePlayerOnStop:(NSArray*)params {
    self.isPlayerOn = NO;
    self.isPlaying = NO;
    self.currentItemPositionInPlaylist = -1;
}

- (void)handlePlaylistGetItems:(NSArray*)params {
    NSInteger itemIndex = -1;
    for(NSDictionary *jsonPlaylistItem in (NSArray*)[params valueForKey:@"items"]) {
        itemIndex++;
        NSString * itemLabel = [jsonPlaylistItem valueForKey:@"label"];
        
        //If the item is not already in the playlist
        if([self.playlistItems count] > itemIndex)
            [self setTitle:itemLabel forItemAtIndex:itemIndex];
        else
            [self addItemWithTitle:itemLabel];
    }
    
    //Update object
    self.playlistItems = self.playlistItems;
    
    [self requestPlayerGetPropertiesPlaylistPosition];
}

- (void)handlePlaylistOnClear {
    NSLog(@"handlePlaylistOnClear");
}

- (void)handlePlaylistOnAdd:(NSArray*)params {
    NSDictionary *item = [[params valueForKey:@"data"] valueForKey:@"item"];
    NSString *itemTitle = [item valueForKey:@"title"];
    [self addItemWithTitle:itemTitle];
    
    //Update object
    self.playlistItems = self.playlistItems;
}


/***** Getters and Setters *****/

- (BOOL)isConnected {
    return (p_socket.readyState == 1);
}

- (void)setIsConnected:(BOOL)connected {
    _isConected = connected;
}

- (void)updatePlaylistStatus {
    self.isPlaylistOn = (self.playlistItemsJson && [self.playlistItemsJson count] > 1);
}

- (BOOL)hasReachedEndOfVideo:(NSInteger)marginInSeconds {
    NSInteger secondsRemaining = 0;
    secondsRemaining  = 3600*(self.playerItemTotalTime.hours - self.playerItemCurrentTime.hours);
    secondsRemaining += 60*(self.playerItemTotalTime.minutes - self.playerItemCurrentTime.minutes);
    secondsRemaining += (self.playerItemTotalTime.seconds - self.playerItemCurrentTime.seconds);
    return (marginInSeconds >= secondsRemaining);
}

- (void)setTitle:(NSString*)title forItemAtIndex:(NSInteger)itemIndex {
    if(!title || !self.playlistItems || itemIndex < 0 || itemIndex >= [self.playlistItems count])
        return;
    KRPlaylistItem * playlistItem = [self.playlistItems objectAtIndex:itemIndex];
    [playlistItem setTitle:title];
}

- (void)addItemWithTitle:(NSString*)title {
    [self.playlistItems addObject:[[KRPlaylistItem alloc] initWithTitle:title]];
}


//    ***     ***   *******    //
//    ***     ***     ***      //
//    ***     ***     ***      //
//    ***     ***     ***      //
//    ***     ***     ***      //
//    ***********     ***      //
//       *****      *******    //

/***** View helpers *****/

- (void)ui_init {
    self.preferredContentSize = CGSizeMake(0, 93);
    p_keyboardBehaviour = COMMAND;
    self.widgetAllowsEditing = YES;
    [self.xib_inputTextToKodiTextField setDelegate:self];
    [self.xib_hostAddressTextField setDelegate:self];
    [self.xib_portTextField setDelegate:self];
    [self.xib_userTextField setDelegate:self];
    [self.xib_passwordTextField setDelegate:self];
    [self.view.window makeFirstResponder:self.view];
}

- (void)ui_enableInterface:(BOOL) enabled {
    //elements to be enabled only when playing a video
    if(!enabled) {
        [self.xib_playerProgressBarSlider setEnabled:NO];
        [self.xib_playerProgressBarSlider setDoubleValue:0.0];
        [self.xib_speedLevelSlider setEnabled:NO];
        [self.xib_playButton setEnabled:NO];
        [self.xib_stopButton setEnabled:NO];
        [self.xib_forwardButton setEnabled:NO];
    }
    [self.xib_goDownButton setEnabled:enabled];
    [self.xib_goLeftButton setEnabled:enabled];
    [self.xib_goRightButton setEnabled:enabled];
    [self.xib_goUpButton setEnabled:enabled];
    [self.xib_okButton setEnabled:enabled];
    [self.xib_menuButton setEnabled:enabled];
    [self.xib_infoButton setEnabled:enabled];
    [self.xib_backButton setEnabled:enabled];
    [self.xib_homeButton setEnabled:enabled];
    [self.xib_volumeLevelSlider setEnabled:enabled];
}

- (void)ui_enableNavigationControls:(BOOL) enabled {
    [self.xib_goDownButton setEnabled:enabled];
    [self.xib_goLeftButton setEnabled:enabled];
    [self.xib_goRightButton setEnabled:enabled];
    [self.xib_goUpButton setEnabled:enabled];
}

- (void)ui_enablePlayerControls:(BOOL) enabled {
    [self.xib_playerProgressBarSlider setEnabled:enabled];
    if(!enabled) [self.xib_playerProgressBarSlider setDoubleValue:0.0];
    [self.xib_speedLevelSlider setEnabled:enabled];
    [self.xib_playButton setEnabled:enabled];
    [self.xib_stopButton setEnabled:enabled];
    [self.xib_forwardButton setEnabled:enabled];
    if(enabled)
        [self.xib_playerProgressTimeTitle setTextColor:[NSColor controlLightHighlightColor]];
    else {
        [self.xib_playerProgressTimeTitle setTextColor:[NSColor quaternaryLabelColor]];
        [self.xib_playerProgressTimeTitle setStringValue:@"0:00:00/0:00:00"];
    }
}

- (void)ui_flash {
    [self.xib_goUpButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.05
                                     target:self.xib_goUpButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
    [self.xib_goDownButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.05
                                     target:self.xib_goDownButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
    [self.xib_goLeftButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.05
                                     target:self.xib_goLeftButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
    [self.xib_goRightButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.05
                                     target:self.xib_goRightButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
    [self.xib_okButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.05
                                     target:self.xib_okButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)ui_updatePlayerTimeTitle {
    [self.xib_playerProgressTimeTitle setStringValue:
     [NSString stringWithFormat:@"%ld:%02ld:%02ld/%ld:%02ld:%02ld",
      self.playerItemCurrentTime.hours,
      self.playerItemCurrentTime.minutes,
      self.playerItemCurrentTime.seconds,
      self.playerItemTotalTime.hours,
      self.playerItemTotalTime.minutes,
      self.playerItemTotalTime.seconds]];
}

- (void)ui_updatePLayerSlider {
    [self.xib_playerProgressBarSlider setDoubleValue:self.playerItemCurrentTimePercentage];
}

- (void)ui_updatePlayerSpeed {
    if(self.playerSpeed == 0)
        [self.xib_playButton setImage:[NSImage imageNamed:@"play"]];
    else
        [self.xib_playButton setImage:[NSImage imageNamed:@"pause"]];
}

- (void)ui_updatePlayerPlayPauseButton:(BOOL) playing {
    if(playing)
        [self.xib_playButton setImage:[NSImage imageNamed:@"play"]];
    else
        [self.xib_playButton setImage:[NSImage imageNamed:@"pause"]];
}

- (void)ui_updateVolume {
    [self.xib_volumeLevelSlider setDoubleValue:self.applicationVolume];
}

- (void)ui_addItemToPlaylistView:(NSString*) itemLabel withPosition:(NSInteger) itemPosition {
    
    if(!itemLabel || [itemLabel isEqualToString:@""]) {
        [self.xib_playlistComboBox addItemWithTitle:[NSString stringWithFormat:@"%02ld. missing item label", itemPosition]];
    } else {
        [self.xib_playlistComboBox addItemWithTitle:[NSString stringWithFormat:@"%02ld. %@", itemPosition, itemLabel]];
//        NSRange range = [itemLabel rangeOfString:@"[0-9]+. .*" options:NSRegularExpressionSearch];
//        if(range.location != NSNotFound)
//            [self.xib_playlistComboBox addItemWithTitle:itemLabel];
//        else
//            [self.xib_playlistComboBox addItemWithTitle:[NSString stringWithFormat:@"%02ld. %@", itemPosition, itemLabel]];
    }
}

- (void)ui_updatePlaylistItems {
    //if playlist is in use
    if(self.playlistItems && [self.playlistItems count] > 1) {
        
        [self.xib_playlistComboBox removeAllItems];
        
        //populating playlist's interface nspopupbutton
        NSInteger itemIndex = 0;
        for(KRPlaylistItem *playListItem in self.playlistItems) {
            itemIndex++;
            [self ui_addItemToPlaylistView:playListItem.title withPosition:itemIndex];
        }
        [self ui_updatePlaylistComboSelect];
        [self ui_showPlaylistControls:YES];
    }
    else {
        [self ui_showPlaylistControls:NO];
    }
}

- (void)ui_updatePlaylistComboSelect {
    [self.xib_playlistComboBox selectItemAtIndex:self.currentItemPositionInPlaylist];
}

- (void)ui_showPlaylistControls:(BOOL) enabled {
    if(enabled)
        self.preferredContentSize = CGSizeMake(0, 120);
    else
        self.preferredContentSize = CGSizeMake(0, 93);
}

- (void)ui_enablePlaylistControls:(BOOL) enabled {
    [self.xib_nextPlaylistItemButton setEnabled:enabled];
    [self.xib_playlistComboBox setEnabled:enabled];
}


/***** View inputs *****/

- (IBAction)onUpButtonPressed:(id)sender {
    [self sendInputUp];
    
    [self.xib_goUpButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_goUpButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onDownButtonPressed:(id)sender {
    [self sendInputDown];
    
    [self.xib_goDownButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_goDownButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onLeftButtonPressed:(id)sender {
    [self sendInputLeft];

    [self.xib_goLeftButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_goLeftButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onRightButtonPressed:(id)sender {
    [self sendInputRight];
    
    [self.xib_goRightButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_goRightButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onOkButtonPressed:(id)sender {
    [self sendInputSelect];
    
    [self.xib_okButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_okButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onBackButtonPressed:(id)sender {
    [self sendInputExecuteActionBack];
    
    [self.xib_backButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_backButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onHomeButtonPressed:(id)sender {
    [self sendInputHome];
    
    [self.xib_homeButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_homeButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onInfoButtonPressed:(id)sender {
    [self sendInputInfo];
    
    [self.xib_infoButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_infoButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onMenuButtonPressed:(id)sender {
    [self sendInputExecuteActionContextMenu];
    
    [self.xib_menuButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_menuButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onStopButtonPressed:(id)sender {
    [self sendInputExecuteActionStop];
    [self ui_showPlaylistControls:NO];
    
    [self.xib_stopButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_stopButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onPlayPauseButtonPressed:(id)sender {
    [self sendInputExecuteActionPause];
    
    [self.xib_playButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_playButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onForwardButtonPressed:(id)sender {
    [self sendPlayerSeekForward];
    
    [self.xib_forwardButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_forwardButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onVolumeSliderChanged:(id)sender {
    int lc_volume = self.xib_volumeLevelSlider.intValue;
    [self sendApplicationSetVolume:lc_volume];
}

- (IBAction)onSpeedSliderChange:(id)sender {
    NSEvent *event = [[NSApplication sharedApplication] currentEvent];
    BOOL endingDrag = event.type == NSLeftMouseUp;
    int lc_speed = self.xib_speedLevelSlider.intValue;
    if( lc_speed != 0 && !endingDrag)
        [self sendPlayerSetSpeed:lc_speed];
    else if (endingDrag) {
        [self sendPlayerSetSpeed:0];
        [self.xib_speedLevelSlider setIntegerValue:0];
    }
}

- (IBAction)onProgressSliderChange:(id)sender {
    NSEvent *event = [[NSApplication sharedApplication] currentEvent];
    if(event.type == NSLeftMouseDragged) {
        long lc_itemDurationH = self.playerItemTotalTime.hours;
        long lc_itemDurationM = self.playerItemTotalTime.minutes;
        long lc_itemDurationS = self.playerItemTotalTime.seconds;
        
        long lc_totalSeconds = lc_itemDurationH*3600 + lc_itemDurationM*60 + lc_itemDurationS;
        NSTimeInterval lc_itemSeek = lc_totalSeconds * ((double)self.xib_playerProgressBarSlider.intValue/100);
        long lc_itemSeekH = lc_itemSeek/3600;
        long lc_itemSeekM = fmod(lc_itemSeek, 3600)/60;
        long lc_itemSeekS = fmod(lc_itemSeek, 60) ;
        
        [self.xib_playerProgressTimeTitle setStringValue:[NSString stringWithFormat:@"%ld:%02ld:%02ld/%ld:%02ld:%02ld",
                                                          lc_itemSeekH,
                                                          lc_itemSeekM,
                                                          lc_itemSeekS,
                                                          lc_itemDurationH,
                                                          lc_itemDurationM,
                                                          lc_itemDurationS]];
    }
    
    if(event.type == NSLeftMouseUp)
        [self sendPlayerSeek:self.xib_playerProgressBarSlider.intValue];
}

- (IBAction)onNextPlaylistItemButtonPressed:(id)sender {
    [self sendPlayerGoToNext];
    
    //UI updates
    [self.xib_nextPlaylistItemButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_nextPlaylistItemButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)onPlaylistComboboxChanged:(id)sender {
    [self sendPlayerGoTo:(int)[sender indexOfSelectedItem]];
    
    //UI updates
    [self.xib_nextPlaylistItemButton highlight:YES];
    [NSTimer scheduledTimerWithTimeInterval:0.1
                                     target:self.xib_nextPlaylistItemButton
                                   selector:@selector(highlight:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if([self.view isHidden])
        return;
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(isInitiated)) ] &&
       ((TodayViewController*)object).isInitiated )
        [self ui_init];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(isConnected)) ])
        [self ui_enableInterface:((TodayViewController*)object).isConnected];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(playerItemCurrentTime))])
        [self ui_updatePlayerTimeTitle];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(playerItemTotalTime))])
        [self ui_updatePlayerTimeTitle];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(playerItemCurrentTimePercentage))])
        [self ui_updatePLayerSlider];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(playerSpeed))])
        [self ui_updatePlayerSpeed];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(applicationVolume))])
        [self ui_updateVolume];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(playlistItems))])
        [self ui_updatePlaylistItems];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(currentItemPositionInPlaylist))])
        [self ui_updatePlaylistComboSelect];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(switchingItemInPlaylist))])
        [self ui_enablePlaylistControls:!self.switchingItemInPlaylist];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(isPlayerOn))])
        [self ui_enablePlayerControls:self.isPlayerOn];
//    else
//    if([keyPath isEqualToString: NSStringFromSelector(@selector(isPlaylistOn))])
//        [self ui_enablePlaylistControls:self.isPlaylistOn];
    else
    if([keyPath isEqualToString: NSStringFromSelector(@selector(isPlaying))])
        [self ui_updatePlayerPlayPauseButton:self.isPlaying];
}


/***** Keyboard inputs *****/

- (void)keyDown:(NSEvent *)event {
//    NSLog(@"Key pressed : %u", event.keyCode);
    switch (p_keyboardBehaviour)
    {
        case TEXT_INPUT:
            break;
        case COMMAND:
            [self keyboardCommandsMapping:event];
            break;
        case SETTINGS:
            break;
    }
}

- (void)keyboardCommandsMapping:(NSEvent *)event {
    NSLog(@"key pressed : %hi", event.keyCode);
    switch (event.keyCode)
    {
        case 1: // s key
            if(event.modifierFlags & NSShiftKeyMask)
                [self onForwardButtonPressed:self];
            else
                [self onStopButtonPressed:self];
            break;
        case 3: // f key
            [self onForwardButtonPressed:self];
            break;
        case 7: // x key
            [self onStopButtonPressed:self];
            break;
        case 8: // c key
            [self onMenuButtonPressed:self];
            break;
        case 11: // b key
            [self sendPlayerSeekBackward];
            break;
        case 13: // w key
            [self sendPlayerMarkAsWatched];
            break;
        case 4:  // h key
            [self onHomeButtonPressed:self];
            break;
        case 32:  // u key
            [self sendVideoLibraryScan];
            break;
        case 34:  // i key
           [self onInfoButtonPressed:self];
            break;
        case 35:  // p key
            [self sendPlayerGoToPrevious];
            break;
        case 36:  // return key
            [self onOkButtonPressed:self];
            break;
        case 43:  // semicolon key
            if(event.modifierFlags & NSCommandKeyMask)
                [self widgetDidBeginEditing];
            break;
        case 45:  // n key
            [self onNextPlaylistItemButtonPressed:self];
            break;
        case 46:  // m key
            [self onMenuButtonPressed:self];
            break;
        case 15:  // r key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendSystemReboot];
            else
            if(event.modifierFlags & NSCommandKeyMask)
                [self reset];
            break;
        case 49:  // space key
            [self onPlayPauseButtonPressed:self];
            break;
        case 51:  // back key
            [self onBackButtonPressed:self];
            break;
        case 123: // left key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendPlayerSeekBackward];
            else
                [self onLeftButtonPressed:self];
            break;
        case 124: // right key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendPlayerSeekForward];
            else
                [self onRightButtonPressed:self];
            break;
        case 125: // down key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendApplicationSetVolumeDecrement];
            else
                [self onDownButtonPressed:self];
            break;
        case 126: // up key
            if(event.modifierFlags & NSShiftKeyMask)
                [self sendApplicationSetVolumeIncrement];
            else
                [self onUpButtonPressed:self];
            break;
        case 48:  // tab key
            [self ui_flash];
            break;
            
        case 9:   // v key
            if(event.modifierFlags & NSCommandKeyMask) {
                NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
                NSString* pastedString = [pasteboard  stringForType:NSPasteboardTypeString];
                [self handleStreamLink:pastedString];
            }
            break;
        default:
            break;
    }
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)commandSelector {

    if([control isEqual:self.xib_inputTextToKodiTextField]) {
        if (commandSelector == @selector(deleteBackward:)) {
            if(self.xib_inputTextToKodiTextField.stringValue.length == 0) {
                [self sendInputExecuteActionBack];
                return YES;
            }
        }
        else if (commandSelector == @selector(insertNewline:)) {
            [self sendInputSendText:self.xib_inputTextToKodiTextField.stringValue andSubmit:YES];
            [self.xib_inputTextToKodiTextField setStringValue:@""];
            return YES;
        }
    }
    else if(commandSelector == @selector(insertNewline:)) {
        if([control isEqual:self.xib_hostAddressTextField]) {
            [self.view.window makeFirstResponder:self.xib_portTextField];
        }
        else if([control isEqual:self.xib_portTextField]) {
            [self.view.window makeFirstResponder:self.xib_userTextField];
        }
        else if([control isEqual:self.xib_userTextField]) {
            if([self.xib_userTextField.stringValue rangeOfString:@" " options:NSRegularExpressionSearch].location != NSNotFound)
                self.xib_userTextField.stringValue = @"";
            [self.view.window makeFirstResponder:self.xib_passwordTextField];
        }
        else if([control isEqual:self.xib_passwordTextField]) {
            if([self.xib_userTextField.stringValue rangeOfString:@" " options:NSRegularExpressionSearch].location != NSNotFound)
                self.xib_passwordTextField.stringValue = @"";
            [self widgetDidEndEditing];
        }
    }
    return NO;
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if([obj.object isEqual:self.xib_inputTextToKodiTextField])
        [self sendInputSendText:self.xib_inputTextToKodiTextField.stringValue andSubmit:NO];
}

- (void)handleStreamLink:(NSString *)link {
    NSString *videoId;
    NSString *plugginSpecificCommand;
    if([link containsString:@"youtube.com/"]) {
        NSRange videoArgPos = [link rangeOfString:@"v="];
        if(videoArgPos.location != NSNotFound) {
            @try {
                videoId = [[link substringFromIndex:videoArgPos.location+2] substringToIndex:11];
                plugginSpecificCommand = [NSString stringWithFormat:@"plugin://plugin.video.youtube/?action=play_video&videoid=%@", videoId];
            }
            @catch (NSException *exception) {
                NSLog(@"Non suitable link");
            }
        }
    }
    else if([link containsString:@"vimeo.com/"]) {
        NSRange videoArgPos = [link rangeOfString:@"vimeo.com/"];
        if(videoArgPos.location != NSNotFound) {
            @try {
                videoId = [[link substringFromIndex:videoArgPos.location+10] substringToIndex:9];
                plugginSpecificCommand = [NSString stringWithFormat:@"plugin://plugin.video.vimeo/play/?video_id=%@", videoId];
                
            }
            @catch (NSException *exception) {
                NSLog(@"Non suitable link");
            }
        }
    }
//    else if([link containsString:@"dailymotion.com/"]) {
//        NSRange videoArgPos = [link rangeOfString:@"video/"];
//        if(videoArgPos.location != NSNotFound) {
//            @try {
//                videoId = [link substringFromIndex:videoArgPos.location+6];
//                plugginSpecificCommand = [NSString stringWithFormat:@"plugin://plugin.video.dailymotion/?action=play_video&videoid=%@", videoId];
//                
//            }
//            @catch (NSException *exception) {
//                NSLog(@"Non suitable link");
//            }
//        }
//    }
    
    if(plugginSpecificCommand != nil) {
        if(p_playerID != 1) { //if Kodi is not playing a video
            [self sendPlaylistClearVideo];
            [self sendPlaylistAddVideoStreamLink:plugginSpecificCommand];
            [self sendPlayerOpenVideo];
        }
        else
            [self sendPlaylistAddVideoStreamLink:plugginSpecificCommand];
    }
}

@end
