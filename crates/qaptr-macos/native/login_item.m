#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>

#include <stdint.h>

int64_t qaptr_smappservice_status(void) {
    @autoreleasepool {
        return (int64_t)SMAppService.mainAppService.status;
    }
}

int32_t qaptr_smappservice_register(int64_t *error_code) {
    @autoreleasepool {
        NSError *error = nil;
        BOOL registered = [SMAppService.mainAppService registerAndReturnError:&error];
        *error_code = error == nil ? 0 : (int64_t)error.code;
        return registered ? 1 : 0;
    }
}

int32_t qaptr_smappservice_unregister(int64_t *error_code) {
    @autoreleasepool {
        NSError *error = nil;
        BOOL unregistered = [SMAppService.mainAppService unregisterAndReturnError:&error];
        *error_code = error == nil ? 0 : (int64_t)error.code;
        return unregistered ? 1 : 0;
    }
}
