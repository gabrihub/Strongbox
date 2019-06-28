//
//  AutoCompleteTextField.m
//  Strongbox-iOS
//
//  Created by Mark on 26/04/2019.
//  Copyright © 2019 Mark McGuill. All rights reserved.
//

#import "AutoCompleteTextField.h"
#import "NSArray+Extensions.h"

@interface AutoCompleteTextField () <UITextFieldDelegate>

@property (nonatomic, strong) NSArray<NSString*> *suggestions;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation AutoCompleteTextField

- (void)awakeFromNib {
    [super awakeFromNib];
    
    self.suggestions = [NSArray array];

    [self addTarget:self
             action:@selector(onTextFieldChanged:)
   forControlEvents:UIControlEventEditingChanged];

    self.delegate = self;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
//    NSLog(@"shouldChangeCharactersInRange: %lu-%lu-%lu", (unsigned long)range.location, (unsigned long)range.length, (unsigned long)textField.text.length);

    if((range.location + range.length) != textField.text.length) { // Only perform autocompletion on end of string edits
        NSLog(@"Not autocompleting as edit is inside string...");
        return YES;
    }
    
    BOOL autoCompleted = [self autoCompleteText:string];
    
    if(autoCompleted) {
        [self onTextFieldChanged:nil]; // AutoCompletes do not send UIControlEventEditingChanged so we call it here manually if there was an autocomplete
    }
    
    return !autoCompleted; // Do not change text if it's been autocompleted already
}

- (void)onTextFieldChanged:(id)sender {
    if(self.onEdited) {
        self.onEdited(self.text);
    }
}

- (BOOL)autoCompleteText:(NSString*)string {
    if (self.suggestionProvider && string.length) {
        UITextRange* prefixRange = [self textRangeFromPosition:self.beginningOfDocument toPosition:self.selectedTextRange.start];
        NSString *text = [self textInRange:prefixRange];
        text = text ? text : @"";
        
        NSString* prefix = [text stringByAppendingString:string];
        
        NSString* match = self.suggestionProvider(prefix);
        
        if (match) {
            self.text = match;
            UITextPosition *start = [self positionFromPosition:self.beginningOfDocument offset:prefix.length];
            
            if (start) {
                self.selectedTextRange = [self textRangeFromPosition:start toPosition:self.endOfDocument];
                return YES;
            }
        }
    }
    
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    self.selectedTextRange =  [self textRangeFromPosition:self.endOfDocument toPosition:self.endOfDocument];
    return YES;
}

@end
