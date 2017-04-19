//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "MessageComposeTableViewController.h"
#import "BlockListUIUtils.h"
#import "ContactTableViewCell.h"
#import "ContactsUpdater.h"
#import "Environment.h"
#import "OWSContactsSearcher.h"
#import "NeverMynd-Swift.h"
#import "UIColor+OWS.h"
#import "UIUtil.h"
#import <MessageUI/MessageUI.h>
#import <SignalServiceKit/OWSBlockingManager.h>

NS_ASSUME_NONNULL_BEGIN

@interface MessageComposeTableViewController () <UISearchBarDelegate,
                                                 UISearchResultsUpdating,
                                                 MFMessageComposeViewControllerDelegate>

@property (nonatomic, readonly) OWSBlockingManager *blockingManager;
@property (nonatomic, readonly) NSArray<NSString *> *blockedPhoneNumbers;

@property (nonatomic) IBOutlet UITableViewCell *inviteCell;
@property (nonatomic) IBOutlet OWSNoSignalContactsView *noSignalContactsView;

@property (nonatomic) UISearchController *searchController;
@property (nonatomic) UIActivityIndicatorView *activityIndicator;
@property (nonatomic) UIView *loadingBackgroundView;

@property (nonatomic, copy) NSArray<Contact *> *contacts;
@property (nonatomic, copy) NSArray<Contact *> *searchResults;
@property (nonatomic, readonly) OWSContactsManager *contactsManager;

// A list of possible phone numbers parsed from the search text as
// E164 values.
@property (nonatomic) NSArray<NSString *> *searchPhoneNumbers;
// A list of possible phone numbers parsed from the search text
// that correspond to known accounts as E164 values.
@property (nonatomic) NSArray<NSString *> *searchPhoneNumberWithAccounts;
// This dictionary is used to cache the set of phone numbers
// which are known to correspond to Signal accounts.
@property (nonatomic, nonnull, readonly) NSMutableSet *phoneNumberAccountSet;

@property (nonatomic) BOOL isNoContactsViewVisible;
@property (nonatomic) UIBarButtonItem *createGroupBarButtonItem;

@end

// The "special" sections are used to display (at most) one of three cells:
//
// * "New conversation for non-contact" if user has entered a phone
//    number which corresponds to a signal account, or:
// * "Send invite via SMS" if user has entered a phone number
//    which is not known to correspond to a signal account, or:
// * "Invite contacts" if the invite flow is available, or:
// * Nothing, otherwise.
typedef NS_ENUM(NSInteger, AdvancedSettingsTableViewControllerSection) {
    MessageComposeTableViewControllerSectionInviteNonContactConversation = 0,
    MessageComposeTableViewControllerSectionInviteViaSMS,
    MessageComposeTableViewControllerSectionInviteFlow,
    MessageComposeTableViewControllerSectionContacts,
    MessageComposeTableViewControllerSection_Count // meta section
};

NSString *const MessageComposeTableViewControllerCellContact = @"ContactTableViewCell";

@implementation MessageComposeTableViewController

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    _contactsManager = [Environment getCurrent].contactsManager;
    _phoneNumberAccountSet = [NSMutableSet set];

    _blockingManager = [OWSBlockingManager sharedManager];
    _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

    [self observeNotifications];

    return self;
}

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    _contactsManager = [Environment getCurrent].contactsManager;

    [self observeNotifications];
    
    return self;
}

- (void)observeNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(signalRecipientsDidChange:)
                                                 name:OWSContactsManagerSignalRecipientsDidChangeNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(blockedPhoneNumbersDidChange:)
                                                 name:kNSNotificationName_BlockedPhoneNumbersDidChange
                                               object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)signalRecipientsDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateContacts];
    });
}

- (void)blockedPhoneNumbersDidChange:(id)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _blockedPhoneNumbers = [_blockingManager blockedPhoneNumbers];

        [self updateContacts];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController.navigationBar setTranslucent:NO];

    self.createGroupBarButtonItem = self.navigationItem.rightBarButtonItem;
    self.navigationItem.rightBarButtonItem.accessibilityLabel = NSLocalizedString(
        @"CREATE_NEW_GROUP", @"Accessibility label for the create group new group button");

    self.tableView.estimatedRowHeight = (CGFloat)60.0;
    self.tableView.rowHeight = UITableViewAutomaticDimension;

    self.contacts = [self filteredContacts];
    self.searchResults = self.contacts;
    [self initializeSearch];

    self.searchController.searchBar.hidden          = NO;
    self.searchController.searchBar.backgroundColor = [UIColor whiteColor];
    self.inviteCell.textLabel.text = NSLocalizedString(
        @"INVITE_FRIENDS_CONTACT_TABLE_BUTTON", @"Text for button at the top of the contact picker");

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    [self createLoadingAndBackgroundViews];
    self.title = NSLocalizedString(@"MESSAGE_COMPOSEVIEW_TITLE", @"");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self showEmptyBackgroundViewIfNecessary];
}

- (UILabel *)createLabelWithFirstLine:(NSString *)firstLine andSecondLine:(NSString *)secondLine {
    UILabel *label      = [[UILabel alloc] init];
    label.textColor     = [UIColor grayColor];
    label.font          = [UIFont ows_regularFontWithSize:18.f];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 4;

    NSMutableAttributedString *fullLabelString =
        [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", firstLine, secondLine]];

    [fullLabelString addAttribute:NSFontAttributeName
                            value:[UIFont ows_boldFontWithSize:15.f]
                            range:NSMakeRange(0, firstLine.length)];
    [fullLabelString addAttribute:NSFontAttributeName
                            value:[UIFont ows_regularFontWithSize:14.f]
                            range:NSMakeRange(firstLine.length + 1, secondLine.length)];
    [fullLabelString addAttribute:NSForegroundColorAttributeName
                            value:[UIColor blackColor]
                            range:NSMakeRange(0, firstLine.length)];
    [fullLabelString addAttribute:NSForegroundColorAttributeName
                            value:[UIColor ows_darkGrayColor]
                            range:NSMakeRange(firstLine.length + 1, secondLine.length)];
    label.attributedText = fullLabelString;
    // 250, 66, 140
    [label setFrame:CGRectMake([self marginSize], 100 + 140, [self contentWidth], 66)];
    return label;
}

- (void)createLoadingAndBackgroundViews {
    // This will be further tweaked per design recs. It must currently be hardcoded (or we can place in separate .xib I
    // suppose) as the controller must be a TableViewController to have access to the native pull to refresh
    // capabilities. That means we can't do a UIView in the storyboard
    _loadingBackgroundView        = [[UIView alloc] initWithFrame:self.tableView.frame];
    UIImageView *loadingImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"uiEmpty"]];
    [loadingImageView setBackgroundColor:[UIColor whiteColor]];
    [loadingImageView setContentMode:UIViewContentModeCenter];
    [loadingImageView setFrame:CGRectMake(self.tableView.frame.size.width / 2.0f - 115.0f / 2.0f, 100, 115, 110)];
    loadingImageView.contentMode = UIViewContentModeCenter;
    loadingImageView.contentMode = UIViewContentModeScaleAspectFit;

    UIActivityIndicatorView *loadingProgressView =
        [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [loadingProgressView
        setFrame:CGRectMake(self.tableView.frame.size.width / 2.0f - loadingProgressView.frame.size.width / 2.0f,
                            100 + 110 / 2.0f - loadingProgressView.frame.size.height / 2.0f,
                            loadingProgressView.frame.size.width,
                            loadingProgressView.frame.size.height)];
    [loadingProgressView setHidesWhenStopped:NO];
    [loadingProgressView startAnimating];
    UILabel *loadingLabel = [self createLabelWithFirstLine:NSLocalizedString(@"LOADING_CONTACTS_LABEL_LINE1", @"")
                                             andSecondLine:NSLocalizedString(@"LOADING_CONTACTS_LABEL_LINE2", @"")];
    [_loadingBackgroundView addSubview:loadingImageView];
    [_loadingBackgroundView addSubview:loadingProgressView];
    [_loadingBackgroundView addSubview:loadingLabel];

    UIButton *inviteButton = self.noSignalContactsView.inviteButton;
    [inviteButton addTarget:self
                     action:@selector(presentInviteFlow)
           forControlEvents:UIControlEventTouchUpInside];
    [inviteButton setTitleColor:[UIColor ows_materialBlueColor]
                                    forState:UIControlStateNormal];
    [inviteButton.titleLabel setFont:[UIFont ows_regularFontWithSize:17.f]];

    UIButton *searchByPhoneNumberButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [searchByPhoneNumberButton setTitle:NSLocalizedString(@"NO_CONTACTS_SEARCH_BY_PHONE_NUMBER",
                                                          @"Label for a button that lets users search for contacts by phone number")
                               forState:UIControlStateNormal];
    [searchByPhoneNumberButton setTitleColor:[UIColor ows_materialBlueColor]
                                    forState:UIControlStateNormal];
    [searchByPhoneNumberButton.titleLabel setFont:[UIFont ows_regularFontWithSize:17.f]];
    [inviteButton.superview addSubview:searchByPhoneNumberButton];
    [searchByPhoneNumberButton autoHCenterInSuperview];
    [searchByPhoneNumberButton autoPinEdge:ALEdgeTop
                                    toEdge:ALEdgeBottom
                                    ofView:inviteButton
                                withOffset:20];
    [searchByPhoneNumberButton addTarget:self
                                  action:@selector(hideBackgroundView)
                        forControlEvents:UIControlEventTouchUpInside];
}

- (void)hideBackgroundView {
    [[Environment preferences] setHasDeclinedNoContactsView:YES];
    
    [self showEmptyBackgroundViewIfNecessary];
}

- (void)presentInviteFlow
{
    OWSInviteFlow *inviteFlow =
        [[OWSInviteFlow alloc] initWithPresentingViewController:self contactsManager:self.contactsManager];
    [self presentViewController:inviteFlow.actionSheetController animated:YES completion:nil];
}

- (void)showLoadingBackgroundView:(BOOL)show {
    if (show) {
        self.searchController.searchBar.hidden = YES;
        self.tableView.backgroundView          = _loadingBackgroundView;
        self.tableView.backgroundView.opaque   = YES;
    } else {
        self.searchController.searchBar.hidden = NO;
        self.tableView.backgroundView          = nil;
    }
}

- (void)showEmptyBackgroundViewIfNecessary {
    self.isNoContactsViewVisible = ([self.contacts count] == 0 &&
                                    ![[Environment preferences] hasDeclinedNoContactsView]);
}

- (void)setIsNoContactsViewVisible:(BOOL)isNoContactsViewVisible {
    if (isNoContactsViewVisible == _isNoContactsViewVisible) {
        return;
    }
    
    _isNoContactsViewVisible = isNoContactsViewVisible;

    if (isNoContactsViewVisible) {
        self.searchController.searchBar.hidden = YES;
        self.tableView.backgroundView = self.noSignalContactsView;
        self.tableView.backgroundView.opaque   = YES;
        self.navigationItem.rightBarButtonItem = nil;
    } else {
        self.searchController.searchBar.hidden = NO;
        self.tableView.backgroundView          = nil;
        self.navigationItem.rightBarButtonItem = self.createGroupBarButtonItem;
    }

    [self.tableView reloadData];
}

#pragma mark - Initializers

- (void)initializeSearch {
    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];

    self.searchController.searchResultsUpdater = self;

    self.searchController.dimsBackgroundDuringPresentation = NO;

    self.searchController.hidesNavigationBarDuringPresentation = NO;

    self.searchController.searchBar.frame = CGRectMake(self.searchController.searchBar.frame.origin.x,
                                                       self.searchController.searchBar.frame.origin.y,
                                                       self.searchController.searchBar.frame.size.width,
                                                       44.0);

    self.tableView.tableHeaderView = self.searchController.searchBar;


    self.searchController.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchController.searchBar.delegate       = self;
    self.searchController.searchBar.placeholder    = NSLocalizedString(@"SEARCH_BYNAMEORNUMBER_PLACEHOLDER_TEXT", @"");
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *searchString = [self.searchController.searchBar text];

    [self filterContentForSearchText:searchString];

    [self.tableView reloadData];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar selectedScopeButtonIndexDidChange:(NSInteger)selectedScope {
    [self updateSearchResultsForSearchController:self.searchController];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
}

#pragma mark - Filter

- (void)filterContentForSearchText:(NSString *)searchText
{
    OWSContactsSearcher *contactsSearcher = [[OWSContactsSearcher alloc] initWithContacts: self.contacts];
    self.searchResults = [contactsSearcher filterWithString:searchText];

    NSMutableArray<NSString *> *searchPhoneNumbers = [NSMutableArray new];
    for (PhoneNumber *phoneNumber in [PhoneNumber tryParsePhoneNumbersFromsUserSpecifiedText:searchText
                                                                           clientPhoneNumber:[TSStorageManager localNumber]]) {
        [searchPhoneNumbers addObject:phoneNumber.toE164];
    }
    // text to a non-signal number if we have no results and a valid phone #
    if (self.searchResults.count == 0 && searchText.length > 8 && searchPhoneNumbers.count > 0) {
        self.searchPhoneNumbers = searchPhoneNumbers;
        // Kick off account lookup if necessary.
        [self checkForAccountsForPhoneNumbers:searchPhoneNumbers];
    } else {
        _searchPhoneNumbers = nil;
    }
}

- (void)checkForAccountsForPhoneNumbers:(NSArray *)phoneNumbers
{
    NSMutableArray<NSString *> *unknownPhoneNumbers = [NSMutableArray new];
    for (NSString *phoneNumber in phoneNumbers) {
        if (![self.phoneNumberAccountSet containsObject:phoneNumber]) {
            [unknownPhoneNumbers addObject:phoneNumber];
        }
    }
    if ([unknownPhoneNumbers count] < 1) {
        return;
    }
    
    __weak MessageComposeTableViewController *weakSelf = self;
    [[ContactsUpdater sharedUpdater] lookupIdentifiers:unknownPhoneNumbers
                                              success:^(NSArray<SignalRecipient *> *recipients) {
                                                  MessageComposeTableViewController *strongSelf = weakSelf;
                                                  if (!strongSelf) {
                                                      return;
                                                  }
                                                  NSUInteger oldCount = strongSelf.phoneNumberAccountSet.count;
                                                  for (SignalRecipient *recipient in recipients) {
                                                      NSString *phoneNumber = recipient.uniqueId;
                                                      [strongSelf.phoneNumberAccountSet addObject:phoneNumber];
                                                  }
                                                  if (oldCount != strongSelf.phoneNumberAccountSet.count) {
                                                      [strongSelf ensureSearchPhoneNumberWithAccounts];
                                                  }
                                              }
                                              failure:^(NSError *error) {
                                                  // Ignore.
                                              }];
}

- (void)setSearchPhoneNumbers:(NSArray<NSString *> *)searchPhoneNumbers {
    if ([_searchPhoneNumbers isEqual:searchPhoneNumbers]) {
        return;
    }
    
    _searchPhoneNumbers = searchPhoneNumbers;
    
    [self ensureSearchPhoneNumberWithAccounts];

    [self.tableView reloadData];
}

- (void)ensureSearchPhoneNumberWithAccounts {
    NSMutableArray<NSString *> *searchPhoneNumberWithAccounts = [NSMutableArray new];
    for (NSString *phoneNumber in self.searchPhoneNumbers) {
        if ([self.phoneNumberAccountSet containsObject:phoneNumber] &&
            ![searchPhoneNumberWithAccounts containsObject:phoneNumber]) {
            [searchPhoneNumberWithAccounts addObject:phoneNumber];
        }
    }
    self.searchPhoneNumberWithAccounts = searchPhoneNumberWithAccounts;
}

- (void)setSearchPhoneNumberWithAccounts:(NSArray<NSString *> *)searchPhoneNumberWithAccounts {
    if ([_searchPhoneNumberWithAccounts isEqual:searchPhoneNumberWithAccounts]) {
        return;
    }
    
    _searchPhoneNumberWithAccounts = searchPhoneNumberWithAccounts;
    
    [self.tableView reloadData];
}

#pragma mark - Send Normal Text to Unknown Contact

- (void)sendTextToPhoneNumber:(NSString *)phoneNumber {
    OWSAssert([phoneNumber length] > 0);
    NSString *confirmMessage = NSLocalizedString(@"SEND_SMS_CONFIRM_TITLE", @"");
    if ([phoneNumber length] > 0) {
        confirmMessage = [[NSLocalizedString(@"SEND_SMS_INVITE_TITLE", @"")
                           stringByAppendingString:phoneNumber]
                          stringByAppendingString:NSLocalizedString(@"QUESTIONMARK_PUNCTUATION", @"")];
    }

    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:NSLocalizedString(@"CONFIRMATION_TITLE", @"")
                                            message:confirmMessage
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"TXT_CANCEL_TITLE", @"")
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction *action) {
                                                           DDLogDebug(@"Cancel action");
                                                         }];

    UIAlertAction *okAction = [UIAlertAction
        actionWithTitle:NSLocalizedString(@"OK", @"")
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  [self.searchController setActive:NO];

                  if ([MFMessageComposeViewController canSendText]) {
                      MFMessageComposeViewController *picker = [[MFMessageComposeViewController alloc] init];
                      picker.messageComposeDelegate          = self;

                      picker.recipients = @[phoneNumber,];
                      picker.body = [NSLocalizedString(@"SMS_INVITE_BODY", @"")
                          stringByAppendingString:
                              @" https://itunes.apple.com/us/app/signal-private-messenger/id874139669?mt=8"];
                      [self presentViewController:picker animated:YES completion:[UIUtil modalCompletionBlock]];
                  } else {
                      UIAlertView *notPermitted =
                          [[UIAlertView alloc] initWithTitle:@""
                                                     message:NSLocalizedString(@"UNSUPPORTED_FEATURE_ERROR", @"")
                                                    delegate:nil
                                           cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                           otherButtonTitles:nil];
                      [notPermitted show];
                  }
                }];

    [alertController addAction:cancelAction];
    [alertController addAction:okAction];
    self.searchController.searchBar.text = @"";

    //must dismiss search controller before presenting alert.
    if ([self presentedViewController]) {
        [self dismissViewControllerAnimated:YES completion:^{
            [self presentViewController:alertController animated:YES completion:[UIUtil modalCompletionBlock]];
        }];
    } else {
        [self presentViewController:alertController animated:YES completion:[UIUtil modalCompletionBlock]];
    }
}

#pragma mark - SMS Composer Delegate

// called on completion of message screen
- (void)messageComposeViewController:(MFMessageComposeViewController *)controller
                 didFinishWithResult:(MessageComposeResult)result {
    switch (result) {
        case MessageComposeResultCancelled:
            break;
        case MessageComposeResultFailed: {
            UIAlertView *warningAlert =
                [[UIAlertView alloc] initWithTitle:@""
                                           message:NSLocalizedString(@"SEND_INVITE_FAILURE", @"")
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                 otherButtonTitles:nil];
            [warningAlert show];
            break;
        }
        case MessageComposeResultSent: {
            [self dismissViewControllerAnimated:NO
                                     completion:^{
                                       DDLogDebug(@"view controller dismissed");
                                     }];
            UIAlertView *successAlert =
                [[UIAlertView alloc] initWithTitle:@""
                                           message:NSLocalizedString(@"SEND_INVITE_SUCCESS", @"Alert body after invite succeeded")
                                          delegate:nil
                                 cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                 otherButtonTitles:nil];
            [successAlert show];
            break;
        }
        default:
            break;
    }

    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return (self.isNoContactsViewVisible
            ? 0
            : MessageComposeTableViewControllerSection_Count);
}

- (BOOL)hasNoContacts
{
    return self.contacts.count == 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // This logic will determine which one (if any) of the following special controls
    // should be shown.  No more than one should be shown at a time.
    BOOL showNonContactConversation = NO;
    BOOL showInviteViaSMS = NO;
    BOOL showInviteFlow = NO;

    BOOL hasPhoneNumber = self.searchPhoneNumbers.count > 0;
    BOOL hasKnownSignalUser = self.searchPhoneNumberWithAccounts.count > 0;
    BOOL isInviteFlowSupported = SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(9, 0);
    if (hasKnownSignalUser) {
        showNonContactConversation = YES;
    } else if (hasPhoneNumber) {
        showInviteViaSMS = YES;
    } else if (isInviteFlowSupported) {
        showInviteFlow = YES;
    }

    if (section == MessageComposeTableViewControllerSectionInviteNonContactConversation) {
        return showNonContactConversation ? (NSInteger) self.searchPhoneNumberWithAccounts.count : 0;
    } else if (section == MessageComposeTableViewControllerSectionInviteViaSMS) {
        return showInviteViaSMS ? (NSInteger) self.searchPhoneNumbers.count : 0;
    } else if (section == MessageComposeTableViewControllerSectionInviteFlow) {
        return showInviteFlow ? 1 : 0;
    } else {
        OWSAssert(section == MessageComposeTableViewControllerSectionContacts)
        
        if (self.searchController.active) {
            return (NSInteger)[self.searchResults count];
        } else {
            if (self.hasNoContacts) {
                return 1;
            }
            return (NSInteger)[self.contacts count];
        }
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == MessageComposeTableViewControllerSectionInviteNonContactConversation) {
        if (indexPath.row < 0 ||
            indexPath.row >= (NSInteger) self.searchPhoneNumberWithAccounts.count) {
            OWSAssert(0);
        }
        NSString *phoneNumber = self.searchPhoneNumberWithAccounts[(NSUInteger) indexPath.row];
        UITableViewCell *conversationForNonContactCell = [UITableViewCell new];
        conversationForNonContactCell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"NEW_CONVERSATION_FOR_NON_CONTACT_FORMAT",
                                                                                                         @"Text for button to start a new conversation with a non-contact"),
                                                             phoneNumber];
        return conversationForNonContactCell;
    } else if (indexPath.section == MessageComposeTableViewControllerSectionInviteViaSMS) {
        if (indexPath.row < 0 ||
            indexPath.row >= (NSInteger) self.searchPhoneNumbers.count) {
            OWSAssert(0);
        }
        NSString *phoneNumber = self.searchPhoneNumbers[(NSUInteger) indexPath.row];
        UITableViewCell *inviteViaSMSCell = [UITableViewCell new];
        inviteViaSMSCell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"SEND_INVITE_VIA_SMS_BUTTON_FORMAT",
                                                                                            @"Text for button to send a Signal invite via SMS. %@ is placeholder for the receipient's phone number."),
                                                phoneNumber];
        return inviteViaSMSCell;
    } else if (indexPath.section == MessageComposeTableViewControllerSectionInviteFlow) {
        return self.inviteCell;
    } else {
        OWSAssert(indexPath.section == MessageComposeTableViewControllerSectionContacts)

        if (!self.searchController.active && self.hasNoContacts)
        {
            UITableViewCell *cell = [UITableViewCell new];
            cell.textLabel.text = NSLocalizedString(
                @"SETTINGS_BLOCK_LIST_NO_CONTACTS", @"A label that indicates the user has no Signal contacts.");
            cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
            cell.textLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            return cell;
        }

        ContactTableViewCell *cell = (ContactTableViewCell *)[tableView
            dequeueReusableCellWithIdentifier:MessageComposeTableViewControllerCellContact];

        Contact *contact = [self contactForIndexPath:indexPath];
        BOOL isBlocked = [self isContactBlocked:contact];
        if (isBlocked) {
            cell.accessoryMessage
                = NSLocalizedString(@"CONTACT_CELL_IS_BLOCKED", @"An indicator that a contact has been blocked.");
        } else {
            OWSAssert(cell.accessoryMessage == nil);
        }
        [cell configureWithContact:contact contactsManager:self.contactsManager];

        return cell;
    }
}

#pragma mark - Table View delegate

- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == MessageComposeTableViewControllerSectionContacts && !self.searchController.active
        && self.hasNoContacts) {
        // Don't let user select the "you have no contacts" cell.
        return nil;
    }

    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    if (indexPath.section == MessageComposeTableViewControllerSectionInviteNonContactConversation) {
        if (indexPath.row < 0 ||
            indexPath.row >= (NSInteger) self.searchPhoneNumberWithAccounts.count) {
            OWSAssert(0);
        }
        NSString *phoneNumber = self.searchPhoneNumberWithAccounts[(NSUInteger) indexPath.row];
        OWSAssert(phoneNumber.length > 0);
        
        if (phoneNumber.length > 0) {
            [self dismissViewControllerAnimated:YES
                                     completion:^() {
                                         [Environment messageIdentifier:phoneNumber withCompose:YES];
                                     }];
        }
    } else if (indexPath.section == MessageComposeTableViewControllerSectionInviteViaSMS) {
        if (indexPath.row < 0 ||
            indexPath.row >= (NSInteger) self.searchPhoneNumbers.count) {
            OWSAssert(0);
        }
        NSString *phoneNumber = self.searchPhoneNumbers[(NSUInteger) indexPath.row];
        [self sendTextToPhoneNumber:phoneNumber];
    } else if (indexPath.section == MessageComposeTableViewControllerSectionInviteFlow) {
        void (^showInvite)() = ^{
            OWSInviteFlow *inviteFlow =
                [[OWSInviteFlow alloc] initWithPresentingViewController:self contactsManager:self.contactsManager];
            [self presentViewController:inviteFlow.actionSheetController
                               animated:YES
                             completion:^{
                                 [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
                             }];
        };

        if (self.presentedViewController) {
            // If search controller is active, dismiss it first.
            [self dismissViewControllerAnimated:YES completion:showInvite];
        } else {
            showInvite();
        }
    } else {
        OWSAssert(indexPath.section == MessageComposeTableViewControllerSectionContacts)

            if (!self.searchController.active && self.hasNoContacts)
        {
            // TODO: We could do something here, like show the "invite contacts" UI.
            return;
        }

        Contact *contact = [self contactForIndexPath:indexPath];
        NSString *contactIdentifier = [[contact textSecureIdentifiers] firstObject];
        [self dismissViewControllerAnimated:YES
                                 completion:^() {
                                     [Environment messageIdentifier:contactIdentifier withCompose:YES];
                                 }];
    }
}

- (Contact *)contactForIndexPath:(NSIndexPath *)indexPath {
    Contact *contact = nil;

    if (self.searchController.active) {
        contact = [self.searchResults objectAtIndex:(NSUInteger)indexPath.row];
    } else {
        contact = [self.contacts objectAtIndex:(NSUInteger)indexPath.row];
    }

    return contact;
}

- (void)updateContacts {
    OWSAssert([NSThread isMainThread]);

    self.contacts = [self filteredContacts];
    [self updateSearchResultsForSearchController:self.searchController];
    [self.tableView reloadData];
}

- (BOOL)isContactHidden:(Contact *)contact
{
    if (contact.parsedPhoneNumbers.count < 1) {
        // Hide contacts without any valid phone numbers.
        return YES;
    }

    return NO;
}

- (BOOL)isContactBlocked:(Contact *)contact
{
    if (contact.parsedPhoneNumbers.count < 1) {
        // Hide contacts without any valid phone numbers.
        return NO;
    }

    for (PhoneNumber *phoneNumber in contact.parsedPhoneNumbers) {
        if ([_blockedPhoneNumbers containsObject:phoneNumber.toE164]) {
            return YES;
        }
    }

    return NO;
}

- (NSArray<Contact *> *_Nonnull)filteredContacts
{
    NSMutableArray<Contact *> *result = [NSMutableArray new];
    for (Contact *contact in self.contactsManager.signalContacts) {
        if (![self isContactHidden:contact]) {
            [result addObject:contact];
        }
    }
    return [result copy];
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(nullable id)sender
{
    self.searchController.active = NO;
}

- (IBAction)closeAction:(id)sender {
    [self.searchController setActive:NO];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (CGFloat)contentWidth {
    return [UIScreen mainScreen].bounds.size.width - 2 * [self marginSize];
}

- (CGFloat)marginSize {
    return 20;
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self.searchController.searchBar resignFirstResponder];
}

@end

NS_ASSUME_NONNULL_END
