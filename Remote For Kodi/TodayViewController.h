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

#import <Cocoa/Cocoa.h>
#import <NotificationCenter/NotificationCenter.h>
#import <SocketRocket/SRWebSocket.h>

#define VERSION_NB "2.0"
#define DEFAULT_ADDRESS "192.168.0.100"
#define DEFAULT_PORT "9090"
#define DEFAULT_USERNAME ""
#define DEFAULT_PASSWORD ""


typedef struct KRPlayerItemTime {
    long hours;
    long minutes;
    long seconds;
} KRPlayerItemTime;



@interface KRPlaylistItem : NSObject {}

/** Title of the item */
@property (readwrite) NSString                               *title;

@end



@interface TodayViewController : NSViewController {}

/** YES after the controller is done initiating */
@property (readonly) BOOL                               isInitiated;

/** YES if the socket is conneted to Kodi */
@property (readonly) BOOL                               isConnected;

/** Currently playing item player position percentage */
@property (readonly) double                             playerItemCurrentTimePercentage;

/** Currently playing item player position percentage */
@property (readonly) KRPlayerItemTime                   playerItemCurrentTime;

/** Currently playing item duration in hours, minutes, seconds */
@property (readonly) KRPlayerItemTime                   playerItemTotalTime;

/** Player's current speed [-32; 32] */
@property (readonly) int                                playerSpeed;

/** Volume level from 0.0 to 100.0 */
@property (readonly) double                             applicationVolume;

/** List of all items in the current playlist */
@property (readonly) NSMutableArray                     *playlistItemsJson;

/** List of all items in the current playlist */
@property (readonly) NSMutableArray<KRPlaylistItem*>    *playlistItems;

/** Position of the current item in the playlist from 0 as the first one */
@property (readonly) NSInteger                          currentItemPositionInPlaylist;

/** Currently playing item's title */
@property (readonly) NSString                           *currentItemTitle;

/** TRUE if the remote asked kodi to switch to another item in the playlist until it's being played */
@property (readonly) BOOL                               switchingItemInPlaylist;

/** TRUE if the player is displayed on kodi */
@property (readonly) BOOL                               isPlayerOn;

/** TRUE if something is playing on kodi */
@property (readonly) BOOL                               isPlaying;

/** TRUE if the playlist contains more than one item */
@property (readonly) BOOL                               isPlaylistOn;


//Main view
@property (strong) IBOutlet     NSView              *xib_mainView;
@property (weak) IBOutlet       NSButton            *xib_goLeftButton;
@property (weak) IBOutlet       NSButton            *xib_goRightButton;
@property (weak) IBOutlet       NSButton            *xib_goUpButton;
@property (weak) IBOutlet       NSButton            *xib_goDownButton;
@property (weak) IBOutlet       NSButton            *xib_okButton;
@property (weak) IBOutlet       NSButton            *xib_backButton;
@property (weak) IBOutlet       NSButton            *xib_menuButton;
@property (weak) IBOutlet       NSButton            *xib_infoButton;
@property (weak) IBOutlet       NSButton            *xib_homeButton;

//Main/Player view
@property (strong) IBOutlet     NSView              *xib_playerView;
@property (weak) IBOutlet       NSButton            *xib_stopButton;
@property (weak) IBOutlet       NSButton            *xib_playButton;
@property (weak) IBOutlet       NSButton            *xib_forwardButton;
@property (weak) IBOutlet       NSSlider            *xib_playerProgressBarSlider;
@property (weak) IBOutlet       NSTextField         *xib_playerProgressTimeTitle;
@property (weak) IBOutlet       NSSlider            *xib_volumeLevelSlider;
@property (weak) IBOutlet       NSSlider            *xib_speedLevelSlider;

// Playlist view
@property (weak) IBOutlet       NSButton            *xib_nextPlaylistItemButton;
@property (weak) IBOutlet       NSPopUpButtonCell   *xib_playlistComboBox;

// Text input view
@property (strong) IBOutlet     NSView              *xib_textView;
@property (weak) IBOutlet       NSTextField         *xib_inputTextToKodiTextField;

// Settings view
@property (strong) IBOutlet     NSView              *xib_settingsView;
@property (weak) IBOutlet       NSTextField         *xib_hostAddressTextField;
@property (weak) IBOutlet       NSTextField         *xib_portTextField;
@property (weak) IBOutlet       NSTextField         *xib_userTextField;
@property (weak) IBOutlet       NSSecureTextField   *xib_passwordTextField;
@property (weak) IBOutlet       NSTextField         *xib_versionTitle;

@end


