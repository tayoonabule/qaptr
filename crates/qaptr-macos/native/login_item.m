#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>

#include <stdint.h>

static NSString *const QaptrHelperBundleIdentifier = @"com.qaptr.helper";

static SMAppService *qaptr_login_item_service(void) {
    return [SMAppService loginItemServiceWithIdentifier:QaptrHelperBundleIdentifier];
}

const char *qaptr_smappservice_identifier(void) {
    @autoreleasepool {
        return QaptrHelperBundleIdentifier.UTF8String;
    }
}

int64_t qaptr_smappservice_status(void) {
    @autoreleasepool {
        return (int64_t)qaptr_login_item_service().status;
    }
}

int32_t qaptr_smappservice_register(int64_t *error_code) {
    @autoreleasepool {
        NSError *error = nil;
        BOOL registered = [qaptr_login_item_service() registerAndReturnError:&error];
        *error_code = error == nil ? 0 : (int64_t)error.code;
        return registered ? 1 : 0;
    }
}

int32_t qaptr_smappservice_unregister(int64_t *error_code) {
    @autoreleasepool {
        NSError *error = nil;
        BOOL unregistered = [qaptr_login_item_service() unregisterAndReturnError:&error];
        *error_code = error == nil ? 0 : (int64_t)error.code;
        return unregistered ? 1 : 0;
    }
}
