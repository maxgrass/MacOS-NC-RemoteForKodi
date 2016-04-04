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
#import <SocketRocket/SRWebSocket.h>

@interface TodayViewController : NSViewController {
    SRWebSocket *p_socket;
}

@property (strong) IBOutlet NSView *mainView;
@property (strong) IBOutlet NSView *playerView;
@property (strong) IBOutlet NSView *textView;
@property (strong) IBOutlet NSView *settingsView;

@property (weak) IBOutlet NSButton *goleftButton;
@property (weak) IBOutlet NSButton *gorightButton;
@property (weak) IBOutlet NSButton *goupButton;
@property (weak) IBOutlet NSButton *godownButton;
@property (weak) IBOutlet NSButton *selectButton;
@property (weak) IBOutlet NSButton *backButton;
@property (weak) IBOutlet NSButton *menuButton;
@property (weak) IBOutlet NSButton *infoButton;
@property (weak) IBOutlet NSButton *homeButton;

@property (weak) IBOutlet NSButton *stopButton;
@property (weak) IBOutlet NSButton *playButton;
@property (weak) IBOutlet NSButton *forwardButton;

@property (weak) IBOutlet NSSlider *playerProgressBar;
@property (weak) IBOutlet NSTextField *playerProgressTime;
@property (weak) IBOutlet NSTextField *playerProgressTotalTime;
@property (weak) IBOutlet NSSlider *volumeLevel;
@property (weak) IBOutlet NSSlider *speedLevel;

@property (weak) IBOutlet NSButton *nextPlaylistItemButton;
@property (weak) IBOutlet NSPopUpButtonCell *playlistCombo;

@property (weak) IBOutlet NSTextField *inputTextTextField;

@property (weak) IBOutlet NSTextField *hostAddress;
@property (weak) IBOutlet NSTextField *port;
@property (weak) IBOutlet NSTextField *userTextField;
@property (weak) IBOutlet NSTextField *passwordTextField;

@end
