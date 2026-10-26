#import <Foundation/Foundation.h>
#import "JJPluralForm.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        if (argc != 2) return 2;
        NSString *root = [NSString stringWithUTF8String:argv[1]];
        NSArray *locales = @[@"fr", @"pt-BR", @"is"];
        NSArray *keys = @[@"WORDS_PLURAL_STRING", @"CHARACTERS_PLURAL_STRING",
                          @"CHARACTERS_NO_SPACES_PLURAL_STRING", @"WORDS_SELECTED_PLURAL_STRING",
                          @"CHARACTERS_SELECTED_PLURAL_STRING", @"CHARACTERS_NO_SPACES_SELECTED_PLURAL_STRING"];
        // Expected user-visible noun forms, independent of resource values.
        NSArray *singular = @[
            @[@"mot", @"caractère", @"caractère (sans espaces)", @"mot sélectionné", @"caractère sélectionné", @"caractère (sans espaces) sélectionné"],
            @[@"palavra", @"caractere", @"caractere (sem espaços)", @"palavra selecionada", @"caractere selecionado", @"caractere (sem espaços) selecionado"],
            @[@"orð", @"stafur", @"stafur (án bila)", @"orð valið", @"stafur valinn", @"stafur (án bila) valinn"]];
        NSArray *plural = @[
            @[@"mots", @"caractères", @"caractères (sans espaces)", @"mots sélectionnés", @"caractères sélectionnés", @"caractères (sans espaces) sélectionnés"],
            @[@"palavras", @"caracteres", @"caracteres (sem espaços)", @"palavras selecionadas", @"caracteres selecionados", @"caracteres (sem espaços) selecionados"],
            @[@"orð", @"stafir", @"stafir (án bila)", @"orð valin", @"stafir valdir", @"stafir (án bila) valdir"]];
        // Each row gives count, singular for French/Brazilian Portuguese,
        // singular for Icelandic. These expected choices do not read the rule.
        NSArray *cases = @[@[@0,@YES,@NO], @[@1,@YES,@YES], @[@2,@NO,@NO],
                          @[@11,@NO,@NO], @[@21,@NO,@YES], @[@101,@NO,@YES],
                          @[@111,@NO,@NO]];
        NSUInteger failures = 0, checks = 0;
        for (NSUInteger locale = 0; locale < locales.count; locale++) {
            NSString *path = [root stringByAppendingPathComponent:
                [NSString stringWithFormat:@"%@.lproj/Localizable.strings", locales[locale]]];
            NSDictionary *strings = [NSDictionary dictionaryWithContentsOfFile:path];
            if (!strings) { NSLog(@"Cannot load %@", path); return 2; }
            JJPluralRule rule = [strings[@"JJ_PLURAL_FORM_RULE"] integerValue];
            for (NSArray *row in cases) {
                NSUInteger count = [row[0] unsignedIntegerValue];
                NSArray *forms = [row[locale < 2 ? 1 : 2] boolValue] ? singular[locale] : plural[locale];
                for (NSUInteger key = 0; key < keys.count; key++) {
                    NSString *expected = [NSString stringWithFormat:@"%lu %@", (unsigned long)count, forms[key]];
                    NSString *actual = [JJPluralForm pluralStringForNumber:count withPluralForms:strings[keys[key]]
                        usingPluralRule:rule localizeNumeral:NO];
                    checks++;
                    if (![actual isEqualToString:expected]) {
                        NSLog(@"FAIL %@ %@ count %lu: expected '%@', got '%@'", locales[locale], keys[key], (unsigned long)count, expected, actual);
                        failures++;
                    }
                }
            }
        }
        NSLog(@"Plural rules: %lu checks, %lu failures", (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
