//
//  RegistrationViewController.h
//  Signal
//
//  Created by Dylan Bourgeois on 13/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CountryCodeViewController.h"


@interface RegistrationViewController : UIViewController <UITextFieldDelegate>

// Country code
@property (nonatomic, strong) IBOutlet UIButton *countryCodeButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *nextButton;

// Phone number
@property (nonatomic, strong) IBOutlet UITextField *phoneNumberTextField;
@property (nonatomic, strong) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *footerLabel;

- (IBAction)unwindToCountryCodeWasSelected:(UIStoryboardSegue *)segue;
- (IBAction)unwindToCountryCodeSelectionCancelled:(UIStoryboardSegue *)segue;

@end
