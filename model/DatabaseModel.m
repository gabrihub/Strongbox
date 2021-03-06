#import "DatabaseModel.h"
#import "Utils.h"
#import "PasswordMaker.h"
#import "SprCompilation.h"
#import "NSArray+Extensions.h"
#import "NSMutableArray+Extensions.h"
#import "DatabaseAuditor.h"
#import "NSData+Extensions.h"
#import "NSDate+Extensions.h"
#import "KeePassConstants.h"
#import "ConcurrentMutableDictionary.h"
#import "MinimalPoolHelper.h"

#if TARGET_OS_IPHONE
#import "KissXML.h" // Drop in replacements for the NSXML stuff available on Mac
#endif

static NSString* const kKeePass1BackupGroupName = @"Backup";
static NSString* const kDefaultRecycleBinTitle = @"Recycle Bin";
static const DatabaseFormat kDefaultDatabaseFormat = kKeePass4;

@interface DatabaseModel ()

@property (nonatomic, readonly) NSMutableDictionary<NSUUID*, NSDate*> *mutableDeletedObjects;
@property (nonatomic, readonly) DatabaseFormat format;
@property (nonatomic, nonnull, readonly) UnifiedDatabaseMetadata* metadata;
@property (nonatomic, nonnull, readonly) CompositeKeyFactors *compositeKeyFactors;

@property (nonatomic, readonly, nonnull) ConcurrentMutableDictionary<NSUUID*, Node*>* fastNodeIdMap;

@end

@implementation DatabaseModel

- (instancetype)init {
    return [self initWithFormat:kDefaultDatabaseFormat];
}

- (instancetype)clone {
    CompositeKeyFactors* ckfClone = [self.ckfs clone];
    UnifiedDatabaseMetadata* metadataClone = [self.metadata clone];
    Node* treeClone = [self.rootNode clone:YES];
    
    return [[DatabaseModel alloc] initWithFormat:self.originalFormat
                             compositeKeyFactors:ckfClone
                                        metadata:metadataClone
                                            root:treeClone
                                  deletedObjects:self.deletedObjects.copy];
}

- (instancetype)initWithFormat:(DatabaseFormat)format {
    return [self initWithFormat:format
            compositeKeyFactors:CompositeKeyFactors.unitTestDefaults];
}

- (instancetype)initWithCompositeKeyFactors:(CompositeKeyFactors *)compositeKeyFactors {
    return [self initWithFormat:kDefaultDatabaseFormat
            compositeKeyFactors:compositeKeyFactors];
}

- (instancetype)initWithFormat:(DatabaseFormat)format
           compositeKeyFactors:(CompositeKeyFactors*)compositeKeyFactors {
    return [self initWithFormat:format
            compositeKeyFactors:compositeKeyFactors
                       metadata:[UnifiedDatabaseMetadata withDefaultsForFormat:format]];
}

- (instancetype)initWithFormat:(DatabaseFormat)format
           compositeKeyFactors:(CompositeKeyFactors *)compositeKeyFactors
                      metadata:(UnifiedDatabaseMetadata*)metadata
            {
    return [self initWithFormat:format
            compositeKeyFactors:compositeKeyFactors
                       metadata:metadata
                           root:nil];
}

- (instancetype)initWithFormat:(DatabaseFormat)format
           compositeKeyFactors:(CompositeKeyFactors *)compositeKeyFactors
                      metadata:(UnifiedDatabaseMetadata *)metadata
                          root:(Node *)root {
    return [self initWithFormat:format
            compositeKeyFactors:compositeKeyFactors
                       metadata:metadata
                           root:root
                 deletedObjects:@{}];
}
    
- (instancetype)initWithFormat:(DatabaseFormat)format
           compositeKeyFactors:(CompositeKeyFactors *)compositeKeyFactors
                      metadata:(UnifiedDatabaseMetadata*)metadata
                          root:(Node *_Nullable)root
                deletedObjects:(NSDictionary<NSUUID *,NSDate *> *)deletedObjects {
    if (self = [super init]) {
        _fastNodeIdMap = [[ConcurrentMutableDictionary alloc] init];
        _format = format;
        _compositeKeyFactors = compositeKeyFactors;
        _metadata = metadata;
        
        _rootNode = root ? root : [self initializeRoot];
        [self rebuildFastNodeIdMap];
 
        _mutableDeletedObjects = deletedObjects.mutableCopy;
    }
    return self;
}



- (Node*)initializeRoot {
    Node* rootGroup = [[Node alloc] initAsRoot:nil childRecordsAllowed:self.format != kKeePass1];

    if (self.format != kPasswordSafe) {
        
        

        NSString *rootGroupName = NSLocalizedString(@"generic_database", @"Database");
        if ([rootGroupName isEqualToString:@"generic_database"]) { 
            rootGroupName = kDefaultRootGroupName;
        }
        Node* keePassRootGroup = [[Node alloc] initAsGroup:rootGroupName parent:rootGroup keePassGroupTitleRules:YES uuid:nil];
        
        [self addChild:keePassRootGroup destination:rootGroup];
    }
    
    return rootGroup;
}



- (NSArray<DatabaseAttachment *> *)attachmentPool {
    return [MinimalPoolHelper getMinimalAttachmentPool:self.rootNode];
}

- (NSSet<NodeIcon *> *)customIconPool {
    NSDictionary<NSUUID *,NSData *> *min = [MinimalPoolHelper getMinimalIconPool:self.rootNode];
    
    NSSet<NodeIcon*> *ret = [min.allValues map:^id _Nonnull(NSData * _Nonnull obj, NSUInteger idx) {
        return [NodeIcon withCustom:obj];
    }].set;
    
    NSLog(@"Got %@ custom icons", @(ret.count));
    
    return ret;
}

- (DatabaseFormat)originalFormat {
    return self.format;
}

- (CompositeKeyFactors *)ckfs {
    return self.compositeKeyFactors;
}

- (UnifiedDatabaseMetadata *)meta {
    return self.metadata;
}

- (Node *)effectiveRootGroup {
    if(self.format == kKeePass || self.format == kKeePass4) {
        
        
        
        
        
        
        if(self.rootNode.children.count > 0) {
            return [self.rootNode.children objectAtIndex:0];
        }
        else {
            return self.rootNode; 
        }
    }
    else {
        return self.rootNode;
    }
}

- (BOOL)isUsingKeePassGroupTitleRules {
    return self.format != kPasswordSafe;
}

- (void)addHistoricalNode:(Node*)item originalNodeForHistory:(Node*)originalNodeForHistory {
    BOOL shouldAddHistory = YES; 
    
    if(shouldAddHistory && !item.isGroup && originalNodeForHistory != nil) {
        [item.fields.keePassHistory addObject:originalNodeForHistory];
    }
}

- (BOOL)setItemTitle:(Node *)item title:(NSString *)title {
    Node* originalNodeForHistory = [item cloneForHistory];

    BOOL ret = [item setTitle:title keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules];

    if (ret) {
        [self addHistoricalNode:item originalNodeForHistory:originalNodeForHistory];
        [item touch:YES touchParents:NO];
    }
    
    return ret;
}



- (void)rebuildFastNodeIdMap {
    [self.fastNodeIdMap removeAllObjects];

    if (self.rootNode && self.rootNode.children) {
        self.fastNodeIdMap[self.rootNode.uuid] = self.rootNode;
        
        for (Node* node in self.rootNode.allChildren) {
            self.fastNodeIdMap[node.uuid] = node;
        }
    }
}

- (BOOL)insertNodeAndTrackNode:(Node*)node parent:(Node*)parent position:(NSInteger)position {
    if (node && parent) {
        BOOL ret = [parent insertChild:node keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules atPosition:position];
        
        self.fastNodeIdMap[node.uuid] = node;
        
        return ret;
    }
    else {
        return NO;
    }
}

- (void)removeNodeFromParentAndTrack:(Node*)node {
    if (node && node.parent) {
        [node.parent removeChild:node];
        [self.fastNodeIdMap removeObjectForKey:node.uuid];
    }
}

- (Node *)getItemById:(NSUUID *)uuid {
    if (uuid == nil) {
        return nil;
    }
    
    return self.fastNodeIdMap[uuid];
}

- (Node *)getItemByCrossSerializationFriendlyId:(NSString*)serializationId {
    if (serializationId.length < 1) {
        return nil;
    }
        
    NSString* prefix = [serializationId substringToIndex:1];
    NSString* suffix = [serializationId substringFromIndex:1];
    
    if (self.format != kPasswordSafe || [prefix isEqualToString:@"R"]) {
        NSUUID* uuid = [[NSUUID alloc] initWithUUIDString:suffix];
        if (uuid) {
            return [self getItemById:uuid];
        }
    }
    else if ([prefix isEqualToString:@"G"]) { 
        return [self.rootNode firstOrDefault:YES predicate:^BOOL(Node * _Nonnull node) {
            NSString *testId = [self getCrossSerializationFriendlyId:node];
            return [testId isEqualToString:serializationId];
        }];
    }
    
    return nil;
}

- (NSString *)getCrossSerializationFriendlyId:(Node *)node {
    if (!node) {
        return nil;
    }
    
    
    
    
    

    BOOL groupCanUseUuid = self.format != kPasswordSafe;
    
    NSString *identifier;
    if(node.isGroup && !groupCanUseUuid) {
        NSArray<NSString*> *titleHierarchy = [node getTitleHierarchy];
        identifier = [titleHierarchy componentsJoinedByString:@":"];
    }
    else {
        identifier = [node.uuid UUIDString];
    }
    
    return [NSString stringWithFormat:@"%@%@", node.isGroup ? @"G" : @"R",  identifier];
}



- (BOOL)isDereferenceableText:(NSString*)text {
    return self.format != kPasswordSafe && [SprCompilation.sharedInstance isSprCompilable:text];
}

- (NSString*)maybeDeref:(NSString*)text node:(Node*)node maybe:(BOOL)maybe {
    return maybe ? [self dereference:text node:node] : text;
}

- (NSString*)dereference:(NSString*)text node:(Node*)node {
    if(self.format == kPasswordSafe || !text.length) {
        return text;
    }
    
    NSError* error;
    
    BOOL isCompilable = [SprCompilation.sharedInstance isSprCompilable:text];
    
    NSString* compiled = isCompilable ? [SprCompilation.sharedInstance sprCompile:text node:node database:self error:&error] : text;
    
    if(error) {
        NSLog(@"WARN: SPR Compilation ERROR: [%@]", error);
    }
    
    return compiled ? compiled : @""; 
}



- (BOOL)preOrderTraverse:(BOOL (^)(Node * _Nonnull))function {
    return [self.rootNode preOrderTraverse:function];
}




- (BOOL)validateMoveItems:(const NSArray<Node*>*)items destination:(Node*)destination {
    NSArray<Node*>* minimalItems = [self getMinimalNodeSet:items].allObjects;
    
    BOOL invalid = [minimalItems anyMatch:^BOOL(Node * _Nonnull obj) {
        return obj.parent == nil || ![obj validateChangeParent:destination keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules];
    }];
    
    return !invalid;
}

- (BOOL)moveItems:(const NSArray<Node *> *)items destination:(Node*)destination {
    return [self moveItems:items destination:destination date:NSDate.date undoData:nil];
}

- (BOOL)moveItems:(const NSArray<Node *> *)items destination:(Node*)destination undoData:(NSArray<NodeHierarchyReconstructionData*>**)undoData {
    return [self moveItems:items destination:destination date:NSDate.date undoData:undoData];
}

- (BOOL)moveItems:(const NSArray<Node *> *_Nonnull)items
      destination:(Node*_Nonnull)destination
             date:(NSDate*_Nonnull)date
         undoData:(NSArray<NodeHierarchyReconstructionData*>**)undoData {
    NSArray<Node*>* minimalItems = [self getMinimalNodeSet:items].allObjects;
    
    BOOL invalid = [minimalItems anyMatch:^BOOL(Node * _Nonnull obj) {
        return obj.parent == nil || ![obj validateChangeParent:destination keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules];
    }];
    
    if (invalid) {
        return NO;
    }
    
    if (undoData) {
        *undoData = [self getHierarchyCloneForReconstruction:items];
    }

    
    
    
    BOOL rollback = NO;
    
    NSMutableArray<Node*> *rollbackTo = NSMutableArray.array;
    for(Node* itemToMove in minimalItems) {
        [rollbackTo addObject:itemToMove.parent];
        
        if(![itemToMove changeParent:destination keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules]) {
            rollback = YES;
            NSLog(@"Error Changing Parents. [%@]", itemToMove);
            break;
        }
    }
    
    if (rollback) {
        int i = 0;
        for (Node* previousParent in rollbackTo) {
            [minimalItems[i++] changeParent:previousParent keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules];
        }
    }
    else {
        for(Node* itemToMove in minimalItems) { 
            [itemToMove touchLocationChanged:date]; 
        }
    }
    
    return !rollback;
}

- (void)undoMove:(NSArray<NodeHierarchyReconstructionData*>*)undoData {
    
    
    
    
    for (NodeHierarchyReconstructionData* reconItem in undoData) {
        Node* originalMovedItem = [self getItemById:reconItem.clonedNode.uuid];
    
        if (originalMovedItem) {
            [self removeNodeFromParentAndTrack:originalMovedItem];
        }
        else {
            
            NSLog(@"WARNWARN: Could not find original moved item! [%@]", reconItem);
        }
    }
    
    
    
    [self reconstruct:undoData];
}




- (BOOL)validateAddChild:(Node *)item destination:(Node *)destination {
    return [destination validateAddChild:item keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules];
}

- (BOOL)addChild:(Node *)item destination:(Node *)destination {
    return [self insertChild:item destination:destination atPosition:-1];
}

- (BOOL)insertChild:(Node *)item destination:(Node *)destination atPosition:(NSInteger)position {
    if( ![destination validateAddChild:item keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules]) {
        return NO;
    }

    return [self insertNodeAndTrackNode:item parent:destination position:position];
}

- (void)removeChildFromParent:(Node *)item {
    [self removeNodeFromParentAndTrack:item];
}



- (BOOL)reorderItem:(Node *)item to:(NSInteger)to {
    NSLog(@"reorderItem: %@ > %lu", item, (unsigned long)index);

    if (item.parent == nil) {
        NSLog(@"WARNWARN: Cannot change order of item, parent is nil");
        return NO;
    }

    NSUInteger currentIndex = [item.parent.children indexOfObject:item];
    if (currentIndex == NSNotFound) {
        NSLog(@"WARNWARN: Cannot change order of item, item not found in parent!");
        return NO;
    }

    if (to >= item.parent.children.count || to < -1) {
        to = -1;
    }
    
    
    BOOL ret = [item.parent reorderChild:item to:to keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules];

    if (ret) {
        [item touchLocationChanged];
    }
    
    return ret;
}

- (BOOL)reorderChildFrom:(NSUInteger)from to:(NSInteger)to parentGroup:(Node*)parentGroup {
    NSLog(@"reorderItem: %lu > %lu", (unsigned long)from, (unsigned long)to);
    
    if (from < 0 || from >= parentGroup.children.count) {
        return NO;
    }
    if(from == to) {
        return YES;
    }
    
    NSLog(@"reorderItem Ok: %lu > %lu", (unsigned long)from, (unsigned long)to);

    Node* item = parentGroup.children[from];
    
    return [self reorderItem:item to:to];
}






- (NSString *)getPathDisplayString:(Node *)vm {
    NSMutableArray<NSString*> *hierarchy = [NSMutableArray array];
    
    Node* current = vm;
    while (current != nil && current != self.effectiveRootGroup) {
        [hierarchy insertObject:current.title atIndex:0];
        current = current.parent;
    }
    
    return hierarchy.count ? [hierarchy componentsJoinedByString:@"/"] : @"/";
}

- (NSString *)getSearchParentGroupPathDisplayString:(Node *)vm {
    if(!vm || vm.parent == nil || vm.parent == self.effectiveRootGroup) {
        return @"/";
    }
    
    NSMutableArray<NSString*> *hierarchy = [NSMutableArray array];
    
    Node* current = vm;
    while (current.parent != nil && current.parent != self.effectiveRootGroup) {
        [hierarchy insertObject:current.parent.title atIndex:0];
        current = current.parent;
    }
    
    NSString *path = [hierarchy componentsJoinedByString:@"/"];
    
    return path;
}

- (NSArray<Node *> *)activeGroups {
    if(self.format == kPasswordSafe) {
        return self.effectiveRootGroup.allChildGroups;
    }
    else if(self.format == kKeePass1) {
        
        Node* keePass1BackupNode = self.keePass1BackupNode;

        return [self.effectiveRootGroup filterChildren:YES predicate:^BOOL(Node * _Nonnull node) {
            return node.isGroup && (keePass1BackupNode == nil || (node != keePass1BackupNode && ![keePass1BackupNode contains:node]));
        }];
    }
    else {
        
        Node* recycleBin = self.recycleBinNode;

        return [self.effectiveRootGroup filterChildren:YES predicate:^BOOL(Node * _Nonnull node) {
            return node.isGroup && (recycleBin == nil || (node != recycleBin && ![recycleBin contains:node]));
        }];
    }
}

- (NSArray<Node *> *)activeRecords {
    if(self.format == kPasswordSafe) {
        return self.effectiveRootGroup.allChildRecords;
    }
    else if(self.format == kKeePass1) {
        
        Node* keePass1BackupNode = self.keePass1BackupNode;

        return [self.effectiveRootGroup filterChildren:YES predicate:^BOOL(Node * _Nonnull node) {
            return !node.isGroup && (keePass1BackupNode == nil || (node != keePass1BackupNode && ![keePass1BackupNode contains:node]));
        }];
    }
    else {
        
        Node* recycleBin = self.recycleBinNode;

        return [self.effectiveRootGroup filterChildren:YES predicate:^BOOL(Node * _Nonnull node) {
            return !node.isGroup && (recycleBin == nil || (node != recycleBin && ![recycleBin contains:node]));
        }];
    }
}

- (NSSet<NSString*> *)urlSet {
    NSMutableSet<NSString*> *bag = [[NSMutableSet alloc]init];
    
    for (Node *recordNode in self.activeRecords) {
        if ([Utils trim:recordNode.fields.url].length > 0) {
            [bag addObject:recordNode.fields.url];
        }
    }
    
    return bag;
}

- (NSSet<NSString*> *)usernameSet {
    NSMutableSet<NSString*> *bag = [[NSMutableSet alloc]init];
    
    for (Node *recordNode in self.activeRecords) {
        if ([Utils trim:recordNode.fields.username].length > 0) {
            [bag addObject:recordNode.fields.username];
        }
    }
    
    return bag;
}

- (NSSet<NSString*> *)tagSet {
    NSArray<NSString*>* allTags = [self.activeRecords flatMap:^NSArray * _Nonnull(Node * _Nonnull obj, NSUInteger idx) {
        return obj.fields.tags.allObjects;
    }];

    NSArray<NSString*>* trimmed = [allTags map:^id _Nonnull(NSString * _Nonnull obj, NSUInteger idx) {
        return [Utils trim:obj];
    }];

    NSArray* filtered = [trimmed filter:^BOOL(NSString * _Nonnull obj) {
        return obj.length > 0;
    }];

    return [NSSet setWithArray:filtered];
}

- (NSSet<NSString*> *)emailSet {
    NSMutableSet<NSString*> *bag = [[NSMutableSet alloc]init];
    
    for (Node *record in self.activeRecords) {
        if ([Utils trim:record.fields.email].length > 0) {
            [bag addObject:record.fields.email];
        }
    }
    
    return bag;
}

- (NSSet<NSString*> *)passwordSet {
    NSMutableSet<NSString*> *bag = [[NSMutableSet alloc]init];
    
    for (Node *record in self.activeRecords) {
        if ([Utils trim:record.fields.password].length > 0) {
            [bag addObject:record.fields.password];
        }
    }
    
    return bag;
}

- (NSString *)mostPopularEmail {
    NSCountedSet<NSString*> *bag = [[NSCountedSet alloc]init];
    
    for (Node *record in self.activeRecords) {
        if(record.fields.email.length) {
            [bag addObject:record.fields.email];
        }
    }
    
    return [self mostFrequentInCountedSet:bag];
}

- (NSString *)mostPopularUsername {
    NSCountedSet<NSString*> *bag = [[NSCountedSet alloc]init];
    
    for (Node *record in self.activeRecords) {
        if(record.fields.username.length) {
            [bag addObject:record.fields.username];
        }
    }
    
    return [self mostFrequentInCountedSet:bag];
}

- (NSString *)mostPopularPassword {
    NSCountedSet<NSString*> *bag = [[NSCountedSet alloc]init];
    
    for (Node *record in self.activeRecords) {
        [bag addObject:record.fields.password];
    }
    
    return [self mostFrequentInCountedSet:bag];
}

-(NSInteger)numberOfRecords {
    return self.effectiveRootGroup.allChildRecords.count;
}

-(NSInteger)numberOfGroups {
    return self.effectiveRootGroup.allChildGroups.count;
}

- (NSString*)mostFrequentInCountedSet:(NSCountedSet<NSString*>*)bag {
    NSString *mostOccurring = nil;
    NSUInteger highest = 0;
    
    for (NSString *s in bag) {
        if ([bag countForObject:s] > highest) {
            highest = [bag countForObject:s];
            mostOccurring = s;
        }
    }
    
    return mostOccurring;
}





- (BOOL)isTitleMatches:(NSString*)searchText node:(Node*)node dereference:(BOOL)dereference {
    NSString* foo = [self maybeDeref:node.title node:node maybe:dereference];
    return [foo localizedStandardContainsString:searchText];
}

- (BOOL)isUsernameMatches:(NSString*)searchText node:(Node*)node dereference:(BOOL)dereference {
    NSString* foo = [self maybeDeref:node.fields.username node:node maybe:dereference];
    return [foo localizedStandardContainsString:searchText];
}

- (BOOL)isPasswordMatches:(NSString*)searchText node:(Node*)node dereference:(BOOL)dereference {
    NSString* foo = [self maybeDeref:node.fields.password node:node maybe:dereference];
    return [foo localizedStandardContainsString:searchText];
}

- (BOOL)isTagsMatches:(NSString*)searchText node:(Node*)node {
    return [node.fields.tags.allObjects anyMatch:^BOOL(NSString * _Nonnull obj) {
        return [obj localizedStandardContainsString:searchText];
    }];
}

- (BOOL)isUrlMatches:(NSString*)searchText node:(Node*)node dereference:(BOOL)dereference {
    NSString* foo = [self maybeDeref:node.fields.url node:node maybe:dereference];
    if([foo localizedStandardContainsString:searchText]) {
        return YES;
    }

    for (NSString* altUrl in node.fields.alternativeUrls) {
        NSString* foo = [self maybeDeref:altUrl node:node maybe:dereference];
        if([foo localizedStandardContainsString:searchText]) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)isAllFieldsMatches:(NSString*)searchText node:(Node*)node dereference:(BOOL)dereference {
    NSString* title = [self maybeDeref:node.title node:node maybe:dereference];
    NSString* username = [self maybeDeref:node.fields.username node:node maybe:dereference];
    NSString* password = [self maybeDeref:node.fields.password node:node maybe:dereference];
    NSString* url = [self maybeDeref:node.fields.url node:node maybe:dereference];
    NSString* email = [self maybeDeref:node.fields.email node:node maybe:dereference];
    NSString* notes = [self maybeDeref:node.fields.notes node:node maybe:dereference];
    
    BOOL simple =   [title localizedStandardContainsString:searchText] ||
    [username localizedStandardContainsString:searchText] ||
    [password localizedStandardContainsString:searchText] ||
    [email localizedStandardContainsString:searchText] ||
    [url localizedStandardContainsString:searchText] ||
    [notes localizedStandardContainsString:searchText];
    
    if(simple) {
        return YES;
    }
    else {
        if (self.format == kKeePass4 || self.format == kKeePass) {
            
            
            for (NSString* tag in node.fields.tags) {
                if ([tag localizedStandardContainsString:searchText]) {
                    return YES;
                }
            }

            
            
            for (NSString* key in node.fields.customFields.allKeys) {
                NSString* value = node.fields.customFields[key].value;
                NSString* derefed = [self maybeDeref:value node:node maybe:dereference];
                
                if ([key localizedStandardContainsString:searchText] || [derefed localizedStandardContainsString:searchText]) {
                    return YES;
                }
            }
        }
        
        
        
        
        if (self.format != kPasswordSafe) {
            BOOL attachmentMatch = [node.fields.attachments.allKeys anyMatch:^BOOL(NSString * _Nonnull obj) {
                return [obj localizedStandardContainsString:searchText];
            }];
            
            if (attachmentMatch) {
                return YES;
            }
        }
    }
    
    return NO;
}

- (NSArray<NSString*>*)getSearchTerms:(NSString *)searchText {
    NSArray* split = [searchText componentsSeparatedByString:@" "];
    NSMutableSet<NSString*>* unique = [NSMutableSet setWithArray:split];
    [unique removeObject:@""];
    
    
    
    return [unique.allObjects sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        return [@(((NSString*)obj2).length) compare:@(((NSString*)obj1).length)];
    }];
}



- (NSString*)getHtmlPrintString:(NSString*)databaseName {
    
    NSString* stylesheet = @"<head><style type=\"text/css\"> \
    body { width: 800px; } \
    .database-title { font-size: 36pt; text-align: center; } \
    .group-title { font-size: 20pt; margin-top:20px; margin-bottom: 5px; text-align: center; font-weight: bold; } \
    .entry-table {  border-collapse: collapse; margin-bottom: 10px; width: 800px; border: 1px solid black; } \
    .entry-title { font-weight: bold; font-size: 16pt; padding: 5px; } \
    table td, table th { border: 1px solid black; } \
    .entry-field-label { width: 100px; padding: 2px; } \
    .entry-field-value { font-family: Menlo; padding: 2px; max-width: 700px; word-wrap: break-word; } \
    </style></head>";
    
    NSMutableString* ret = [NSMutableString stringWithFormat:@"<html>%@\n<body>\n    <h1 class=\"database-title\">%@</h1>\n<h6>Printed: %@</h6>    ", stylesheet, [self htmlStringFromString:databaseName], NSDate.date.iso8601DateString];
    
    NSArray<Node*>* sortedGroups = [self.effectiveRootGroup.allChildGroups sortedArrayUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        NSString* path1 = [self getPathDisplayString:obj1];
        NSString* path2 = [self getPathDisplayString:obj2];
        return finderStringCompare(path1, path2);
    }];
    
    NSMutableArray* allGroups = sortedGroups.mutableCopy;
    [allGroups addObject:self.effectiveRootGroup];
    
    for(Node* group in allGroups) {
        [ret appendFormat:@"    <div class=\"group-title\">%@</div>\n", [self htmlStringFromString:[self getPathDisplayString:group]]];
        
        NSMutableArray* nodeStrings = @[].mutableCopy;
        
        NSArray* sorted = [group.childRecords sortedArrayUsingComparator:finderStyleNodeComparator];
        
        for(Node* entry in sorted) {
            NSString* nodeString = [self getHtmlStringForNode:entry];
            [nodeStrings addObject:nodeString];
        }
        
        NSString* groupString = [nodeStrings componentsJoinedByString:@"\n    "];
        
        [ret appendString:groupString];
        [ret appendString:@"    </tr>\n"];
    }
    
    [ret appendString:@"</body>\n</html>"];
    return ret.copy;
}

- (NSString*)getHtmlStringForNode:(Node*)entry {
    NSMutableString* str = [NSMutableString string];
    
    [str appendFormat:@"        <table class=\"entry-table\"><tr class=\"entry-title\"><td colspan=\"100\">%@</td></tr>\n", entry.title];
    
    if(entry.fields.username.length) {
        [str appendString:[self getHtmlEntryFieldRow:@"Username" value:entry.fields.username]];
        [str appendString:@"\n"];
    }
    
    [str appendString:[self getHtmlEntryFieldRow:@"Password" value:entry.fields.password]];
    [str appendString:@"\n"];

    if(entry.fields.url.length) {
        [str appendString:[self getHtmlEntryFieldRow:@"URL" value:entry.fields.url]];
        [str appendString:@"\n"];
    }
    
    if (self.format == kPasswordSafe && entry.fields.email.length) {
        [str appendString:[self getHtmlEntryFieldRow:@"Email" value:entry.fields.email]];
        [str appendString:@"\n"];
    }
    
    if (entry.fields.notes.length) {
        [str appendString:[self getHtmlEntryFieldRow:@"Notes" value:entry.fields.notes]];
        [str appendString:@"\n"];
    }
    
    
    
    if(entry.fields.expires) {
        [str appendString:[self getHtmlEntryFieldRow:@"Expires" value:entry.fields.expires.iso8601DateString]];
        [str appendString:@"\n"];
    }

    
    
    if(entry.fields.customFields.count) {
        for (NSString* key in entry.fields.customFields.allKeys) {
            StringValue* v = entry.fields.customFields[key];
            [str appendString:[self getHtmlEntryFieldRow:key value:v.value]];
            [str appendString:@"\n"];
        }
    }
    
    [str appendString:@"</table>\n"];
    
    return str.copy;
}

- (NSString*)getHtmlEntryFieldRow:(NSString*)label value:(NSString*)value {
    return [NSString stringWithFormat:@"        <tr class=\"entry-field-row\"><td class=\"entry-field-label\">%@</td><td class = \"entry-field-value\">%@</td></tr>", label, [self htmlStringFromString:value]];
}

- (NSString*)htmlStringFromString:(NSString*)str {
    NSXMLNode *textNode = [NSXMLNode textWithStringValue:str];
    NSString *escapedString = textNode.XMLString;
    
    return [[escapedString stringByReplacingOccurrencesOfString:@"\r\n" withString:@"<br>"] stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>"];
}



- (void)performPreSerializationTidy {
    [self trimKeePassHistory];
}

- (void)trimKeePassHistory {
    [self trimKeePassHistory:self.metadata.historyMaxItems maxSize:self.metadata.historyMaxSize];
}

- (void)trimKeePassHistory:(NSNumber*)maxItems maxSize:(NSNumber*)maxSize {
    for(Node* record in self.rootNode.allChildRecords) {
        [self trimNodeKeePassHistory:record maxItems:maxItems maxSize:maxSize];
    }
}

- (BOOL)trimNodeKeePassHistory:(Node*)node maxItems:(NSNumber*)maxItemsNum maxSize:(NSNumber*)maxSizeNum {
    bool trimmed = false;
    
    NSInteger maxItems = maxItemsNum != nil ? maxItemsNum.integerValue : kDefaultHistoryMaxItems;
    NSInteger maxSize = maxSizeNum != nil ? maxSizeNum.integerValue : kDefaultHistoryMaxSize;
    
    if(maxItems >= 0)
    {
        while(node.fields.keePassHistory.count > maxItems)
        {
            [self removeOldestHistoryItem:node];
            trimmed = YES;
        }
    }
    
    if(maxSize >= 0)
    {
        while(true)
        {
            NSUInteger histSize = 0;
            
            for (Node* historicalNode in node.fields.keePassHistory) {
                histSize += [self getEstimatedSize:historicalNode];
            }
            
            if(histSize > maxSize)
            {
                [self removeOldestHistoryItem:node];
                trimmed = YES;
            }
            else {
                break;
            }
        }
    }
    
    return trimmed;
}

- (NSUInteger)getEstimatedSize:(Node*)node {
    
    NSUInteger fixedStructuralSizeGuess = 256;
    
    NSUInteger basicFields = node.title.length +
    node.fields.username.length +
    node.fields.password.length +
    node.fields.url.length +
    node.fields.notes.length;
    
    NSUInteger customFields = 0;
    for (NSString* key in node.fields.customFields.allKeys) {
        customFields += key.length + node.fields.customFields[key].value.length;
    }
    
    
    
    NSUInteger historySize = 0;
    for (Node* historyNode in node.fields.keePassHistory) {
        historySize += [self getEstimatedSize:historyNode];
    }
    
    
    
    NSUInteger iconSize = node.icon ? node.icon.estimatedStorageBytes : 0UL;
        
    
    
    NSUInteger binariesSize = 0;
    for (NSString* filename in node.fields.attachments.allKeys) {
        DatabaseAttachment* dbA = node.fields.attachments[filename];
        binariesSize += dbA == nil ? 0 : dbA.estimatedStorageBytes;
    }
    
    NSUInteger textSize = (basicFields + customFields) * 2; 
    
    NSUInteger ret = fixedStructuralSizeGuess + textSize + historySize + iconSize + binariesSize;

    
    
    return ret;
}

- (void)removeOldestHistoryItem:(Node*)node {
    NSArray* sorted = [node.fields.keePassHistory sortedArrayUsingComparator:^NSComparisonResult(Node*  _Nonnull obj1, Node*  _Nonnull obj2) {
        return [obj1.fields.modified compare:obj2.fields.modified];
    }];
    
    if(sorted.count < 2) {
        [node.fields.keePassHistory removeAllObjects];
    }
    else {
        node.fields.keePassHistory = [[sorted subarrayWithRange:NSMakeRange(1, sorted.count - 1)] mutableCopy];
    }
}




- (void)setDeletedObjects:(NSDictionary<NSUUID *,NSDate *> *)deletedObjects {
    [self.mutableDeletedObjects removeAllObjects];
    [self.mutableDeletedObjects addEntriesFromDictionary:deletedObjects];
}

- (NSDictionary<NSUUID *,NSDate *> *)deletedObjects {
    return self.mutableDeletedObjects.copy;
}

- (BOOL)canRecycle:(Node *)item {
    BOOL willRecycle = self.recycleBinEnabled;
    
    if(self.recycleBinEnabled && self.recycleBinNode) {
        if([self.recycleBinNode contains:item] || self.recycleBinNode == item) {
            willRecycle = NO;
        }
    }

    return willRecycle;
}

- (void)deleteAllGroupItems:(Node*)group deletionDate:(NSDate*)deletionDate {
    for (Node* entry in group.childRecords) {
        [self removeNodeFromParentAndTrack:entry];
        self.mutableDeletedObjects[entry.uuid] = deletionDate;
    }

    for (Node* subgroup in group.childGroups) {
        [self deleteAllGroupItems:subgroup deletionDate:deletionDate];
        self.mutableDeletedObjects[subgroup.uuid] = deletionDate;
    }
}

- (NSArray<NodeHierarchyReconstructionData*>*)getHierarchyCloneForReconstruction:(const NSArray<Node*>*)items {
    return [items map:^id _Nonnull(Node * _Nonnull obj, NSUInteger idx) {
        NodeHierarchyReconstructionData* recon = [[NodeHierarchyReconstructionData alloc] init];
        
        recon.index = [obj.parent.children indexOfObject:obj];
        recon.clonedNode = [obj clone:YES];
        
        return recon;
    }];
}

- (void)reconstruct:(NSArray<NodeHierarchyReconstructionData*>*)undoData {
    for (NodeHierarchyReconstructionData* recon in undoData) {
        Node* parent = recon.clonedNode.parent;
        
        if (!parent) {
            continue; 
        }
        
        [self addChild:recon.clonedNode destination:parent];
        
        NSUInteger currentIndex = parent.children.count - 1;
        if (currentIndex != recon.index) {
            if (! [parent reorderChildAt:currentIndex to:recon.index keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules] ) {
                NSLog(@"WARNWARN: Could not reorder child from %lu to %lu during reconstruction.", (unsigned long)currentIndex, (unsigned long)recon.index);
            }
        }
    }
}

- (void)unDelete:(NSArray<NodeHierarchyReconstructionData*>*)undoData {
    [self reconstruct:undoData];
    
    for (NodeHierarchyReconstructionData* recon in undoData) {
        
        NSArray<NSUUID*>* childIds = [recon.clonedNode.allChildren map:^id _Nonnull(Node * _Nonnull obj, NSUInteger idx) {
            return obj.uuid;
        }];
        
        [self.mutableDeletedObjects removeObjectForKey:recon.clonedNode.uuid];
        [self.mutableDeletedObjects removeObjectsForKeys:childIds];
    }
}

- (void)deleteItems:(const NSArray<Node *> *)items {
    [self deleteItems:items undoData:nil];
}

- (void)deleteItems:(const NSArray<Node *> *)items undoData:(NSArray<NodeHierarchyReconstructionData*>**)undoData {
    NSDate* now = NSDate.date;
    NSSet<Node*> *minimalNodeSet = [self getMinimalNodeSet:items];
    
    if (undoData) {
        *undoData = [self getHierarchyCloneForReconstruction:items];
    }
    
    for (Node* item in minimalNodeSet) {
        if (item.parent == nil || ![item.parent contains:item]) { 
            NSLog(@"WARNWARN: Attempt to delete item with no parent");
            return;
        }

        if (item.isGroup) {
            [self deleteAllGroupItems:item deletionDate:now];
        }

        [self removeNodeFromParentAndTrack:item];
        self.mutableDeletedObjects[item.uuid] = now;
    }
}

- (BOOL)recycleItems:(const NSArray<Node *> *)items {
    return [self recycleItems:items undoData:nil];
}

- (BOOL)recycleItems:(const NSArray<Node *> *)items undoData:(NSArray<NodeHierarchyReconstructionData*>**)undoData {
    if (!self.recycleBinEnabled) {
        NSLog(@"WARNWARN: Attempt to recycle item when recycle bin disabled!");
        return NO;
    }
    
    if(self.recycleBinNode == nil) {     
        [self createNewRecycleBinNode];
    }
    
    NSDate* now = NSDate.date;
    NSSet<Node*> *minimalNodeSet = [self getMinimalNodeSet:items];

    BOOL ret = [self moveItems:minimalNodeSet.allObjects destination:self.recycleBinNode date:now undoData:undoData];
    
    if (ret) {
        for (Node* item in minimalNodeSet) { 
            [item touchAt:now]; 
        }
    }

    return ret;
}

- (void)undoRecycle:(NSArray<NodeHierarchyReconstructionData*>*)undoData {
    [self undoMove:undoData];
}

- (void)setRecycleBinEnabled:(BOOL)recycleBinEnabled {
    self.metadata.recycleBinEnabled = recycleBinEnabled;
}

- (BOOL)recycleBinEnabled {
    return self.metadata.recycleBinEnabled;
}

- (NSUUID *)recycleBinNodeUuid {
    return self.metadata.recycleBinGroup;
}

- (void)setRecycleBinNodeUuid:(NSUUID *)recycleBinNode {
    self.metadata.recycleBinGroup = recycleBinNode;
}
- (NSDate *)recycleBinChanged {
    return self.metadata.recycleBinChanged;
}

- (void)setRecycleBinChanged:(NSDate *)recycleBinChanged {
    self.metadata.recycleBinChanged = recycleBinChanged;
}

- (Node *)recycleBinNode {
    return [self getItemById:self.recycleBinNodeUuid];
}

- (Node*)keePass1BackupNode {
    return [self.effectiveRootGroup firstOrDefault:NO predicate:^BOOL(Node * _Nonnull node) {
        return [node.title isEqualToString:kKeePass1BackupGroupName];
    }];
}

- (void)createNewRecycleBinNode {
    Node* recycleBin = [[Node alloc] initAsGroup:kDefaultRecycleBinTitle parent:self.effectiveRootGroup keePassGroupTitleRules:self.isUsingKeePassGroupTitleRules uuid:nil];
    recycleBin.icon = [NodeIcon withPreset:43];
    
    [self addChild:recycleBin destination:self.effectiveRootGroup];

    self.recycleBinNodeUuid = recycleBin.uuid;
    self.recycleBinChanged = [NSDate date];
}



- (NSSet<Node*>*)getMinimalNodeSet:(const NSArray<Node*>*)nodes {
    
    
    
    NSArray<Node*>* groups = [nodes filter:^BOOL(Node * _Nonnull obj) {
        return obj.isGroup;
    }];
    
    NSArray<Node*>* minimalNodeSet = [nodes filter:^BOOL(Node * _Nonnull node) {
        BOOL alreadyContained = [groups anyMatch:^BOOL(Node * _Nonnull group) {
            return [group contains:node];
        }];
        return !alreadyContained;
    }];
    
    return [NSSet setWithArray:minimalNodeSet];
}

@end
