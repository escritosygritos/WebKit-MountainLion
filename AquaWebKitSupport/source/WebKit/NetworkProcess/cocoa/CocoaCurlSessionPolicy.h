/*
 * SPDX-License-Identifier: BSD-2-Clause
 */
#pragma once

#include <CoreFoundation/CFDictionary.h>
#include <Security/SecProtocolTypes.h>
#include <wtf/RetainPtr.h>

namespace WebKit {

// Transport policy selected by a credential/privacy session partition.
struct CocoaCurlSessionPolicy {
    tls_protocol_version_t minimumTLSProtocol;
    bool presentsPreferredIdentity;
    RetainPtr<CFDictionaryRef> proxySettings;
};

}
