//
//  ServicesSource.m
//
//  Copyright (c) 2009  Martin Kuehl <purl.org/net/mkhl>
//  Licensed under the MIT License.
//

#import <Vermilion/Vermilion.h>

#pragma mark ServiceEntry Keys
NSString *kServicesEntryNameKeyPath = @"NSMenuItem.default";
NSString *kServicesEntryBundleIdentifierKey = @"NSBundleIdentifier";
NSString *kServicesEntryBundlePathKey = @"NSBundlePath";
NSString *kServicesEntryReturnTypesKey = @"NSReturnTypes";
NSString *kServicesEntrySendTypesKey = @"NSSendTypes";

#pragma mark HGSResult Keys
NSString *kServicesDataKey = @"ServicesData";
NSString *kServicesItemKey = @"ServicesItem";
NSString *kServicesNameKey = @"ServicesName";

#pragma mark HGSResult Types
NSString *kServicesDataResultType = HGS_SUBTYPE(@"action", @"service");
NSString *kServicesItemResultType = HGS_SUBTYPE(@"script", @"service");

#pragma mark Static Data
static NSString *kServicesDataNameFormat = @"Perform service with %@";
static NSString *kServicesSnippetFormat = @"A service of %@";
static NSString *kServicesPerformAction = @"org.purl.net.mkhl.services.action.perform";
static NSString *kServicesURLFormat = @"qsb-service://%@";

#pragma mark -
#pragma mark Helper Functions
NSArray *CFServiceControllerCopyServicesEntries(void);

static NSArray *_ServicesPboardTypesForResult(const HGSResult *result)
{
    if ([result conformsToType:kHGSTypeWebpage])
        return [NSArray arrayWithObjects:NSStringPboardType, NSURLPboardType, nil];
    if ([result conformsToType:kHGSTypeFile])
        return [NSArray arrayWithObjects:NSStringPboardType, NSFilenamesPboardType, nil];
    return [NSArray arrayWithObject:NSStringPboardType];
}

static id _ServicesObjectForType(const NSString *type, const HGSResult *result)
{
    if ([type isEqual:NSURLPboardType])
        return [result url];
    if ([type isEqual:NSFilenamesPboardType])
        return [NSArray arrayWithObject:[[result url] absoluteString]];
    return [[result url] absoluteString];
}

static NSDictionary *_ServicesDataForQuery(const NSString *query)
{
    return [NSDictionary dictionaryWithObject:query forKey:NSStringPboardType];
}

static NSDictionary *_ServicesDataForResult(const HGSResult *result)
{
    NSMutableDictionary *data = [NSMutableDictionary dictionary];
    for (NSString *type in _ServicesPboardTypesForResult(result))
        [data setObject:_ServicesObjectForType(type, result) forKey:type];
    return data;
}

static NSPredicate *_ServicesPredicateForQuery(const HGSQuery *query)
{
    return [NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForConstantValue:[query uniqueWords]]
                                              rightExpression:[NSExpression expressionForKeyPath:kServicesEntryNameKeyPath]
                                                     modifier:NSAllPredicateModifier
                                                         type:NSInPredicateOperatorType
                                                      options:(NSCaseInsensitivePredicateOption |
                                                               NSDiacriticInsensitivePredicateOption)];
}

static NSPredicate *_ServicesPredicateForResult(const HGSResult *result)
{
    return [NSComparisonPredicate predicateWithLeftExpression:[NSExpression expressionForConstantValue:_ServicesPboardTypesForResult(result)]
                                              rightExpression:[NSExpression expressionForKeyPath:kServicesEntrySendTypesKey]
                                                     modifier:NSAnyPredicateModifier
                                                         type:NSInPredicateOperatorType
                                                      options:0];
}

static HGSAction *_ServicesPerformAction(void)
{
    return [[HGSExtensionPoint actionsPoint] extensionWithIdentifier:kServicesPerformAction];
}

static NSURL *_ServicesURLForService(const NSString *name)
{
    return [NSURL URLWithString:[NSString stringWithFormat:kServicesURLFormat, [name stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
}

static NSURL *_ServicesURLForQuery(const NSString *name, const NSString *query)
{
    return [NSURL URLWithString:[query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] relativeToURL:_ServicesURLForService(name)];
}

#pragma mark -
@interface ServicesSource : HGSCallbackSearchSource
- (BOOL) isValidSourceForQuery:(HGSQuery *)query;
- (NSArray *) servicesForQuery:(HGSQuery *)query;
- (HGSResult *) resultForService:(NSDictionary *)service withPivot:(HGSResult *)pivot;
- (HGSResult *) resultForQuery:(HGSQuery *)query;
- (void) performSearchOperation:(HGSSearchOperation *)operation;
@end

#pragma mark -
@implementation ServicesSource

- (BOOL) isValidSourceForQuery:(HGSQuery *)query
{
    if (![super isValidSourceForQuery:query])
        return NO;
    HGSResult *pivot = [query pivotObject];
    if (pivot == nil)
        return YES;
    if ([pivot isOfType:kServicesItemResultType]) {
        if ([[query uniqueWords] count] == 0)
            return NO;
        if (![_ServicesPredicateForResult(pivot) evaluateWithObject:[pivot valueForKey:kServicesItemKey]])
            return NO;
    }
    return YES;
}

- (NSArray *) servicesForQuery:(HGSQuery *)query
{
    NSArray *services = CFServiceControllerCopyServicesEntries();
    NSPredicate *byName = _ServicesPredicateForQuery(query);
    HGSResult *pivot = [query pivotObject];
    if (pivot == nil)
        return [services filteredArrayUsingPredicate:byName];
    NSPredicate *byType = _ServicesPredicateForResult(pivot);
    return [services filteredArrayUsingPredicate:[NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObjects:byName, byType, nil]]];
}

- (HGSResult *) resultForService:(NSDictionary *)service withPivot:(HGSResult *)pivot
{
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    NSString *name = [service valueForKeyPath:kServicesEntryNameKeyPath];
    NSString *path = [service valueForKey:kServicesEntryBundlePathKey];
    [attrs setObject:[NSString stringWithFormat:kServicesSnippetFormat, [[NSFileManager defaultManager] displayNameAtPath:path]]
              forKey:kHGSObjectAttributeSnippetKey];
    [attrs setObject:[[NSWorkspace sharedWorkspace] iconForFile:path]
              forKey:kHGSObjectAttributeIconKey];
    [attrs setObject:service forKey:kServicesItemKey];
    [attrs setObject:name forKey:kServicesNameKey];
    HGSAction *action = _ServicesPerformAction();
    if (action) {
        [attrs setObject:action forKey:kHGSObjectAttributeDefaultActionKey];
    }
    if (pivot) {
        [attrs setObject:_ServicesDataForResult(pivot) forKey:kServicesDataKey];
    }
    return [HGSResult resultWithURL:_ServicesURLForService(name)
                               name:[name lastPathComponent]
                               type:kServicesItemResultType
                             source:self
                         attributes:attrs];
}

- (HGSResult *) resultForQuery:(HGSQuery *)query
{
    NSString *queryString = [query rawQueryString];
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    HGSResult *pivot = [query pivotObject];
    NSString *name = [pivot valueForKey:kServicesNameKey];
    [attrs setObject:name forKey:kServicesNameKey];
    [attrs setObject:[pivot valueForKey:kServicesItemKey] forKey:kServicesItemKey];
    [attrs setObject:_ServicesDataForQuery(queryString) forKey:kServicesDataKey];
    HGSAction *action = _ServicesPerformAction();
    if (action) {
        [attrs setObject:action forKey:kHGSObjectAttributeDefaultActionKey];
        [attrs setObject:[action icon] forKey:kHGSObjectAttributeIconKey];
    }
    return [HGSResult resultWithURL:_ServicesURLForQuery(name, queryString)
                               name:[NSString stringWithFormat:kServicesDataNameFormat, queryString]
                               type:kServicesDataResultType
                             source:self
                         attributes:attrs];
}

- (void) performSearchOperation:(HGSSearchOperation *)operation
{
    HGSQuery *query = [operation query];
    HGSResult *pivot = [query pivotObject];
    if (pivot && [pivot isOfType:kServicesItemResultType]) {
        [operation setResults:[NSArray arrayWithObject:[self resultForQuery:query]]];
        return;
    }
    NSArray *services = [self servicesForQuery:query];
    NSMutableArray *results = [NSMutableArray arrayWithCapacity:[services count]];
    for (NSDictionary *service in services)
        [results addObject:[self resultForService:service withPivot:pivot]];
    [operation setResults:results];
}

@end
