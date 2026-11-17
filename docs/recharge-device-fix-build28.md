# Build 28 — recharge context and visible water-device checks

## Recharge

Both official bridge endpoints returned HTTP 200 and business code 0 on the connected iPhone. Build 27 nevertheless rejected their encrypted identifiers using exact equality with stored ciphertext. The official HAR also shows loginBySysId returning an identifier different from its request.

Use the authenticated bridge response owner and its bound-card response. Require a bound login and nonempty owner; select the configured card if exactly matched, otherwise accept only one bound card. Multiple unmatched or duplicate cards remain ambiguous. Do not bypass authentication or synthesize credentials.

Live verification on the user's iPhone 16 Pro Max: card recharge renders balance and amount options; electricity recharge renders building selection, and Other Buildings opens the official electricity payment/location page. No amount selected, payment submitted or recharge performed. Electricity location still requires selection in the official page.

## Water

Read-only discovery has separate progress/error state from the last use/settlement. After hardware identity matching, display device name, water-controller number, signal, abbreviated peripheral UUID, candidate count and verification time. A failed scan must not claim successful verification or turn an already settled session into an unsettled one. No water authorization is part of inspection.

## Validation

76 XCTest cases and 41 Swift Testing tests passed; simulator compile and signed device build passed. Existing app data was backed up before an in-place update. Debug builds contain private configuration and must not be published.

Connected-phone read-only water check completed successfully: matched one BT19-S device to the configured hardware identifier. Device details, signal and verification time were visible in the native accessibility tree. Previous settlement state remained settled. All 14 pre-update support files remain; the WaterSession session file is byte-identical.
