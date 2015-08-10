//
//  ViewController.m
//  OSX Remote For Kodi
//
//  Created by Sylvain on 09/08/2015.
//  Copyright (c) 2015 SylvainRoux. All rights reserved.
//

#import "ViewController.h"

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (IBAction)close:(id)sender {
    [NSApp terminate:self];
}

@end
