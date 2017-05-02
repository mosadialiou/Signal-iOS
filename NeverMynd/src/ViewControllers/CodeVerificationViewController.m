//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "CodeVerificationViewController.h"
#import "AppDelegate.h"
#import "NeverMynd-Swift.h"
#import "SignalsNavigationController.h"
#import "SignalsViewController.h"
#import "StringUtil.h"
#import <PromiseKit/AnyPromise.h>
#import <SignalServiceKit/OWSError.h>
#import <SignalServiceKit/TSAccountManager.h>
#import <SignalServiceKit/TSNetworkManager.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const kCompletedRegistrationSegue = @"CompletedRegistration";

@interface CodeVerificationViewController () <UITextFieldDelegate>
@property (weak, nonatomic) IBOutlet UIBarButtonItem *doneButton;

@property (nonatomic, readonly) AccountManager *accountManager;

// Where the user enters the verification code they wish to document
@property (nonatomic) UITextField *challengeTextField;

@property (nonatomic) UILabel *phoneNumberLabel;

@property (nonatomic) UILabel *footerUILabel;

//// User action buttons
@property (nonatomic) UIButton *challengeButton;

@property (nonatomic) UIActivityIndicatorView *submitCodeSpinner;
@property (nonatomic) UIActivityIndicatorView *requestCodeAgainSpinner;
@property (nonatomic) UIActivityIndicatorView *requestCallSpinner;

@property (nonatomic) NSMutableArray *digitArray;

@end

#pragma mark -

@implementation CodeVerificationViewController

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _accountManager = [Environment getCurrent].accountManager;

    return self;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _accountManager = [Environment getCurrent].accountManager;

    return self;
}

#pragma mark - View Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self createViews];
    
    [self initializeKeyboardHandlers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self enableServerActions:YES];
    [self updatePhoneNumberLabel];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_challengeTextField becomeFirstResponder];
}

#pragma mark - 

- (void)createViews {
    self.view.backgroundColor = [UIColor whiteColor];
    self.view.opaque = YES;
    
    _phoneNumberLabel = [UILabel new];
    _phoneNumberLabel.textColor = [UIColor ows_darkGrayColor];
    _phoneNumberLabel.font = [UIFont ows_regularFontWithSize:20.f];
    _phoneNumberLabel.numberOfLines = 2;
    _phoneNumberLabel.adjustsFontSizeToFitWidth = YES;
    [self.view addSubview:_phoneNumberLabel];
    [_phoneNumberLabel autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5(32)];
    
    [_phoneNumberLabel autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:ScaleFromIPhone5To7Plus(60, 130)];

    const CGFloat kHMargin = 36;
    
    UIView *container = [UIView new];
    [self.view addSubview:container];
    
    [container autoPinWidthToSuperviewWithMargin:kHMargin];
    [container autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:_phoneNumberLabel
                          withOffset:25];
    
    [self buildCodeViews: container];

    _footerUILabel = [UILabel new];
    _footerUILabel.text = @"You should receive a SMS with the code in 88 seconds.";
    _footerUILabel.textColor = [UIColor ows_darkGrayColor];
    _footerUILabel.font = [UIFont ows_regularFontWithSize:20.f];
    _footerUILabel.numberOfLines = 0;
    _footerUILabel.adjustsFontSizeToFitWidth = YES;
    [self.view addSubview:_footerUILabel];
    [_footerUILabel autoPinWidthToSuperviewWithMargin:ScaleFromIPhone5(32)];
    [_footerUILabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:container
                        withOffset:25];
}

- (void) buildCodeViews: (UIView *) container{
    
    _digitArray = [[NSMutableArray alloc] init];
    
     const CGFloat kHMargin = 20;
    
    id previous = nil;
    
    const int number = 6;
    
    const float factor = 1.0f / number;
    
    const double constant = factor * 5 * kHMargin;
    
    for(int i = 0; i < number; i++) {
       UITextField *txtField = [UITextField new];
        txtField.textColor = [UIColor blackColor];
        txtField.font = [UIFont ows_lightFontWithSize:21.f];
        txtField.textAlignment = NSTextAlignmentCenter;
        txtField.keyboardType = UIKeyboardTypeNumberPad;
        txtField.delegate    = self;
        
        [container addSubview:txtField];
        
        [[NSLayoutConstraint constraintWithItem:txtField attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:container attribute:NSLayoutAttributeWidth multiplier:(factor) constant: -constant] setActive:YES];
        
        [txtField autoPinEdgeToSuperviewEdge:ALEdgeTop];
        
        UIView *underscoreView = [UIView new];
        underscoreView.backgroundColor = [UIColor colorWithWhite:0.5 alpha:1.f];
        [container addSubview:underscoreView];
        
        [underscoreView autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:txtField
                         withOffset:3];
        [underscoreView autoPinEdge:ALEdgeLeading toEdge:ALEdgeLeading ofView:txtField];
        [underscoreView autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:txtField];
        [underscoreView autoSetDimension:ALDimensionHeight toSize:1.f];
        [underscoreView autoPinEdgeToSuperviewEdge:ALEdgeBottom];
        
        if(previous != nil){
            [txtField autoPinEdge:ALEdgeLeading toEdge:ALEdgeTrailing ofView:previous withOffset:kHMargin];
        }else {
            [txtField autoPinEdgeToSuperviewEdge:ALEdgeLeading];
        }
        
        if(i == 0){
            _challengeTextField = txtField;
        }
        
        previous = txtField;
        
        [_digitArray addObject:txtField];
    }
}

- (NSString *)phoneNumberText
{
    OWSAssert([TSAccountManager localNumber] != nil);
    return [PhoneNumber bestEffortFormatPartialUserSpecifiedTextToLookLikeAPhoneNumber:[TSAccountManager localNumber]];
}

- (void)updatePhoneNumberLabel
{
    _phoneNumberLabel.text =
        [NSString stringWithFormat:NSLocalizedString(@"VERIFICATION_PHONE_NUMBER_FORMAT",
                                       @"Label indicating the phone number currently being verified."),
                  [self phoneNumberText]];
}

- (void)startActivityIndicator
{
    [self.submitCodeSpinner startAnimating];
    [self enableServerActions:NO];
    [self.challengeTextField resignFirstResponder];
    _doneButton.enabled = NO;

}

- (void)stopActivityIndicator
{
    [self enableServerActions:YES];
    [self.submitCodeSpinner stopAnimating];
    _doneButton.enabled = YES;
}
- (IBAction)verifyCode:(id)sender {
    [self verifyChallengeAction:sender];
}

- (void)verifyChallengeAction:(nullable id)sender
{
    [self startActivityIndicator];
    [self.accountManager registerWithVerificationCode:[self validationCodeFromTextField]]
        .then(^{
            DDLogInfo(@"%@ Successfully registered Signal account.", self.tag);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopActivityIndicator];
                [self performSegueWithIdentifier:kCompletedRegistrationSegue sender:nil];
            });
        })
        .catch(^(NSError *_Nonnull error) {
            DDLogError(@"%@ error verifying challenge: %@", self.tag, error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self stopActivityIndicator];
                [self presentAlertWithVerificationError:error];
            });
        });
}


- (void)presentAlertWithVerificationError:(NSError *)error
{
    UIAlertController *alertController;
    // In the case of the "rate limiting" error, we want to show the
    // "recovery suggestion", not the error's "description."
    if ([error.domain isEqualToString:TSNetworkManagerDomain] &&
        error.code == 413) {
        alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_TITLE",
                                                                      @"Alert view title")
                                                              message:error.localizedRecoverySuggestion
                                                       preferredStyle:UIAlertControllerStyleAlert];
    } else {
        alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"REGISTRATION_VERIFICATION_FAILED_TITLE",
                                                                                        @"Alert view title")
                                                              message:error.localizedDescription
                                                       preferredStyle:UIAlertControllerStyleAlert];
    }
    UIAlertAction *dismissAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"DISMISS_BUTTON_TEXT", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *action) {
                                                              [_challengeTextField becomeFirstResponder];
                                                          }];
    [alertController addAction:dismissAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (NSString *)validationCodeFromTextField {
    NSMutableString *code = [NSMutableString new];
    for(id txt in _digitArray) {
        [code appendString:((UITextField *)txt).text];
    }
    return code;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(nullable id)sender
{
    DDLogInfo(@"%@ preparing for CompletedRegistrationSeque", self.tag);
    if ([segue.identifier isEqualToString:kCompletedRegistrationSegue]) {
        if (![segue.destinationViewController isKindOfClass:[SignalsNavigationController class]]) {
            DDLogError(@"%@ Unexpected destination view controller: %@", self.tag, segue.destinationViewController);
            return;
        }

        SignalsNavigationController *snc = (SignalsNavigationController *)segue.destinationViewController;

        AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
        appDelegate.window.rootViewController = snc;
        if (![snc.topViewController isKindOfClass:[SignalsViewController class]]) {
            DDLogError(@"%@ Unexpected top view controller: %@", self.tag, snc.topViewController);
            return;
        }

        DDLogDebug(@"%@ notifying signals view controller of new user.", self.tag);
        SignalsViewController *signalsViewController = (SignalsViewController *)snc.topViewController;
        signalsViewController.newlyRegisteredUser = YES;
    }
}

#pragma mark - Send codes again

- (void)showRegistrationErrorMessage:(NSError *)registrationError {
    UIAlertView *registrationErrorAV = [[UIAlertView alloc] initWithTitle:registrationError.localizedDescription
                                                                  message:registrationError.localizedRecoverySuggestion
                                                                 delegate:nil
                                                        cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                        otherButtonTitles:nil, nil];

    [registrationErrorAV show];
}

- (void)enableServerActions:(BOOL)enabled {
    [_challengeButton setEnabled:enabled];
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

- (BOOL)textField:(UITextField *)textField
    shouldChangeCharactersInRange:(NSRange)range
                replacementString:(NSString *)insertionText {
    
    textField.text = insertionText;
    
    int count = (int)_digitArray.count;
    for(int i=0; i< count; i++){
        NSUInteger pos = (NSUInteger) i;
        if([textField.text length] != 0 &&  i < (count -1) && [_digitArray objectAtIndex:pos] == textField){
            [[_digitArray objectAtIndex:pos+1] becomeFirstResponder];
            break;
        }
    }
    
    _doneButton.enabled = [self codeInserted];
    
    return NO;
}

-(BOOL) codeInserted {
    for(id txtField in _digitArray){
        if([((UITextField *)txtField).text length] == 0) return NO;
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self verifyChallengeAction:nil];
    [textField resignFirstResponder];
    return NO;
}

- (void)setVerificationCodeAndTryToVerify:(NSString *)verificationCode {
    NSString *rawNewText = verificationCode.digitsOnly;
    NSString *formattedNewText = (rawNewText.length <= 3
                                  ? rawNewText
                                  : [[[rawNewText substringToIndex:3]
                                      stringByAppendingString:@"-"]
                                     stringByAppendingString:[rawNewText substringFromIndex:3]]);
    self.challengeTextField.text = formattedNewText;
    // Move the cursor after the newly inserted text.
    UITextPosition *newPosition = [self.challengeTextField endOfDocument];
    self.challengeTextField.selectedTextRange = [self.challengeTextField textRangeFromPosition:newPosition
                                                                                    toPosition:newPosition];
    [self verifyChallengeAction:nil];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end

NS_ASSUME_NONNULL_END
