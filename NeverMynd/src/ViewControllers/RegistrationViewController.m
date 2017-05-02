//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "RegistrationViewController.h"
#import "CodeVerificationViewController.h"
#import "Environment.h"
#import "PhoneNumber.h"
#import "PhoneNumberUtil.h"
#import "SignalKeyingStorage.h"
#import "TSAccountManager.h"
#import "UIView+OWS.h"
#import "Util.h"
#import "ViewControllerUtils.h"

static NSString *const kCodeSentSegue = @"codeSent";

@interface RegistrationViewController ()

@property (nonatomic) NSString *callingCode;

@end

#pragma mark -

@implementation RegistrationViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    _phoneNumberTextField.delegate = self;
    _phoneNumberTextField.keyboardType = UIKeyboardTypeNumberPad;
    [self populateDefaultCountryNameAndCode];
    [[Environment getCurrent] setSignUpFlowNavigationController:self.navigationController];

    _titleLabel.text = NSLocalizedString(@"REGISTRATION_TITLE_LABEL", @"");
    _phoneNumberTextField.placeholder = NSLocalizedString(
        @"REGISTRATION_ENTERNUMBER_DEFAULT_TEXT", @"Placeholder text for the phone number textfield");
    
    _footerLabel.text = NSLocalizedString(@"REGISTRATION_FOOTER_LABEL", @"");
    
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [_phoneNumberTextField becomeFirstResponder];
}

#pragma mark - Country

- (void)populateDefaultCountryNameAndCode {
    NSLocale *locale      = NSLocale.currentLocale;
    NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
    NSNumber *callingCode = [[PhoneNumberUtil sharedUtil].nbPhoneNumberUtil getCountryCodeForRegion:countryCode];
    NSString *countryName = [PhoneNumberUtil countryNameFromCountryCode:countryCode];
    [self updateCountryWithName:countryName
                    callingCode:[NSString stringWithFormat:@"%@%@",
                                 COUNTRY_CODE_PREFIX,
                                 callingCode]
                    countryCode:countryCode];
}

- (void)updateCountryWithName:(NSString *)countryName
                  callingCode:(NSString *)callingCode
                  countryCode:(NSString *)countryCode {

    _callingCode = callingCode;

    NSString *title = [NSString stringWithFormat:@"%@ (%@)",
                       countryName,
                       callingCode];
    [_countryCodeButton setTitle:title
                        forState:UIControlStateNormal];
}

#pragma mark - Actions

- (IBAction)didTapExistingUserButton:(id)sender
{
    DDLogInfo(@"called %s", __PRETTY_FUNCTION__);

    NSString *alertTitleFormat = NSLocalizedString(@"EXISTING_USER_REGISTRATION_ALERT_TITLE",
        @"during registration, embeds {{device type}}, e.g. \"iPhone\" or \"iPad\"");
    NSString *alertTitle = [NSString stringWithFormat:alertTitleFormat, [UIDevice currentDevice].localizedModel];
    NSString *alertBody = NSLocalizedString(@"EXISTING_USER_REGISTRATION_ALERT_BODY", @"during registration");
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:alertTitle
                                                                             message:alertBody
                                                                      preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction =
        [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleCancel handler:nil];
    [alertController addAction:cancelAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (IBAction)sendCodeAction:(id)sender {
    NSString *phoneNumber = [NSString stringWithFormat:@"%@%@", _callingCode, _phoneNumberTextField.text];
    PhoneNumber *localNumber = [PhoneNumber tryParsePhoneNumberFromUserSpecifiedText:phoneNumber];

    [_nextButton setEnabled:NO];
    
    [_phoneNumberTextField resignFirstResponder];

    [TSAccountManager registerWithPhoneNumber:localNumber.toE164
        success:^{
            [_nextButton setEnabled:YES];
          [self performSegueWithIdentifier:kCodeSentSegue sender:self];
        }
        failure:^(NSError *error) {
          if (error.code == 400) {
              SignalAlertView(NSLocalizedString(@"REGISTRATION_ERROR", nil),
                              NSLocalizedString(@"REGISTRATION_NON_VALID_NUMBER", ));
          } else {
              SignalAlertView(error.localizedDescription, error.localizedRecoverySuggestion);
          }
            
            [_nextButton setEnabled:YES];
        }
        smsVerification:YES];
}

- (IBAction)changeCountryCodeTapped {
    CountryCodeViewController *countryCodeController = [CountryCodeViewController new];
    [self presentViewController:countryCodeController animated:YES completion:[UIUtil modalCompletionBlock]];
}

- (void)presentInvalidCountryCodeError {
    UIAlertView *alertView =
        [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_TITLE", @"")
                                   message:NSLocalizedString(@"REGISTER_CC_ERR_ALERT_VIEW_MESSAGE", @"")
                                  delegate:nil
                         cancelButtonTitle:NSLocalizedString(@"DISMISS_BUTTON_TEXT",
                                               @"Generic short text for button to dismiss a dialog")
                         otherButtonTitles:nil];
    [alertView show];
}

#pragma mark - Keyboard notifications

- (void)initializeKeyboardHandlers {
    UITapGestureRecognizer *outsideTabRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboardFromAppropriateSubView)];
    [self.view addGestureRecognizer:outsideTabRecognizer];
}

- (void)dismissKeyboardFromAppropriateSubView {
    [self.view endEditing:NO];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText {

    [ViewControllerUtils phoneNumberTextField:textField
                shouldChangeCharactersInRange:range
                            replacementString:insertionText
                                  countryCode:_callingCode];
    
    _nextButton.enabled = _phoneNumberTextField.hasText;

    return NO; // inform our caller that we took care of performing the change
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendCodeAction:nil];
    [textField resignFirstResponder];
    return NO;
}

#pragma mark - Unwind segue

- (IBAction)unwindToChangeNumber:(UIStoryboardSegue *)sender {
}

- (IBAction)unwindToCountryCodeSelectionCancelled:(UIStoryboardSegue *)segue {
}

- (IBAction)unwindToCountryCodeWasSelected:(UIStoryboardSegue *)segue {
    CountryCodeViewController *vc = [segue sourceViewController];
    [self updateCountryWithName:vc.countryNameSelected
                    callingCode:vc.callingCodeSelected
                    countryCode:vc.countryCodeSelected];

    // Reformat phone number
    [self textField:_phoneNumberTextField shouldChangeCharactersInRange:NSMakeRange(0, 0) replacementString:@""];
}


@end
