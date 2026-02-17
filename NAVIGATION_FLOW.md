# Driver Registration Flow

## Navigation Flow Map

```
Driver Home Screen
    ↓ (Try to go online)
    | → Profile Incomplete?
    |     ↓
    |   [Dialog: Complete Profile]
    |     ↓ (Click "Complete Profile")
    |   Document Checklist Screen
    |
    | → Not Approved?
    |     ↓
    |   [Dialog: Pending Approval]
    |     ↓ (Click "View Status")
    |   Document Checklist Screen
    |
    ↓ (All complete & approved)
  ✅ Goes Online Successfully
```

## Document Checklist Screen Flow

```
Document Checklist Screen
├── Status Card
│   ├── ✅ Approved → Green
│   ├── ⏳ Pending → Orange
│   ├── ❌ Rejected → Red
│   └── 📝 Incomplete → Blue
│
├── Section 1: Driving License
│   ├── License Front [Upload/Replace/Delete]
│   └── License Back [Upload/Replace/Delete]
│
├── Section 2: Vehicle Documents
│   ├── Private Hire Licence [Upload/Replace/Delete]
│   ├── Road Tax [Upload/Replace/Delete]
│   ├── MOT Certificate [Upload/Replace/Delete]
│   └── Insurance [Upload/Replace/Delete]
│
├── Vehicle Information
│   └── [Add/Edit] → Vehicle Information Screen
│       ├── Category Dropdown
│       ├── Model Input
│       ├── Number Input
│       └── Color Input
│
└── Info Card
    └── Instructions & Requirements
```

## Upload Flow

```
User clicks Upload Icon
    ↓
Choose Source Dialog
    ├── 📷 Camera
    ├── 🖼️ Gallery
    └── 📁 Files (PDF/DOC)
    ↓
File Selected
    ↓
Validation
    ├── ❌ > 10MB → Error Message
    ├── ❌ Wrong Format → Error Message
    └── ✅ Valid
        ↓
    Upload to API
        ↓
    POST /api/v1/drivers/documents/:type
        ↓
    Response
        ├── ✅ Success → Update UI, Show Checkmark
        └── ❌ Failed → Error Message
        ↓
    Refresh Profile Status
        ↓
    GET /api/v1/drivers/profile-status
        ↓
    Update Status Card
```

## Go Online Flow

```
Driver toggles "Go Online"
    ↓
PATCH /api/v1/drivers/status
Body: { "isOnline": true }
    ↓
Response Check
    ├── ✅ success: true
    │   ↓
    │   Driver goes online
    │   Start location updates
    │   Listen for ride requests
    │
    ├── ❌ code: "PROFILE_INCOMPLETE"
    │   ↓
    │   Show Dialog: "Upload missing documents"
    │   [Complete Profile] → Navigate to Document Checklist
    │
    ├── ❌ code: "NOT_APPROVED"
    │   ↓
    │   Show Dialog: "Pending admin approval"
    │   [View Status] → Navigate to Document Checklist
    │
    └── ❌ Other Error
        ↓
        Show error message
```

## Profile Status States

### State 1: Incomplete (Blue)
```
isComplete: false
verificationStatus: "pending"
canGoOnline: false
missingItems: { ..., ... }  // Has true values
```
**Action:** Upload missing documents

### State 2: Complete - Pending (Orange)
```
isComplete: true
verificationStatus: "pending"
canGoOnline: false
missingItems: all false
```
**Action:** Wait for admin approval

### State 3: Approved (Green)
```
isComplete: true
verificationStatus: "approved"
canGoOnline: true
missingItems: all false
```
**Action:** Can go online!

### State 4: Rejected (Red)
```
isComplete: varies
verificationStatus: "rejected"
canGoOnline: false
```
**Action:** Contact support

## API Call Sequence

### Initial Load
```
1. App opens
2. GET /api/v1/drivers/me (fetch driver profile)
3. GET /api/v1/drivers/profile-status
4. Display current status
```

### Upload Document
```
1. User picks file
2. Validate file (size, format)
3. POST /api/v1/drivers/documents/:type
   - Field: document (multipart/form-data)
4. Receive response
5. GET /api/v1/drivers/profile-status (auto-refresh)
6. Update UI
```

### Update Vehicle
```
1. User fills form
2. Validate inputs
3. PATCH /api/v1/drivers/update
   Body: { "vehicle": { ... } }
4. Receive response
5. GET /api/v1/drivers/profile-status (auto-refresh)
6. Update UI
```

### Delete Document
```
1. User confirms deletion
2. DELETE /api/v1/drivers/documents/:type
3. Receive response
4. GET /api/v1/drivers/profile-status (auto-refresh)
5. Update UI (show as missing)
```

## Data Models

### DocumentType Enum
```dart
enum DocumentType {
  licenseFront,      // Section 1
  licenseBack,       // Section 1
  privateHireLicence, // Section 2
  roadTax,           // Section 2
  mot,               // Section 2
  insurance          // Section 2
}
```

### DriverProfileStatus Model
```dart
{
  "isComplete": bool,
  "verificationStatus": "pending" | "approved" | "rejected",
  "canGoOnline": bool,
  "missingItems": {
    "licenseFront": bool,
    "licenseBack": bool,
    "privateHireLicence": bool,
    "roadTax": bool,
    "mot": bool,
    "insurance": bool,
    "vehicleImages": bool,
    "vehicleDetails": bool
  }
}
```

## Code Entry Points

### To Navigate to Document Checklist:
```dart
Navigator.pushNamed(context, '/driver/documents');
```

### To Navigate to Vehicle Info:
```dart
Navigator.pushNamed(context, '/driver/vehicle-info');
```

### To Upload Document:
```dart
final auth = Provider.of<AuthProvider>(context, listen: false);
await auth.uploadDocument('licenseFront', File('path'));
```

### To Check Status:
```dart
final auth = Provider.of<AuthProvider>(context, listen: false);
await auth.fetchDriverProfileStatus();
final statusData = auth.driverProfileStatus;
final status = DriverProfileStatus.fromJson(statusData);
```

## Integration Points

### Driver Profile Screen
- Menu item: "Document Checklist"
- Shows missing count badge
- Tappable → navigates to checklist

### Driver Home Screen
- Go Online toggle
- Catches `PROFILE_INCOMPLETE` error
- Catches `NOT_APPROVED` error
- Shows dialogs with navigation

### Auth Provider
- `uploadDocument(type, file)`
- `deleteDocument(type)`
- `updateVehicleInformation(...)`
- `fetchDriverProfileStatus()`
- Auto-refreshes status after ops

## File Structure
```
lib/
├── core/
│   ├── models/
│   │   └── driver_document.dart [NEW]
│   ├── constants/
│   │   └── api_constants.dart [UPDATED]
│   ├── api_service.dart [UPDATED]
│   └── auth_provider.dart [UPDATED]
├── features/
│   └── driver/
│       ├── document_checklist_screen.dart [NEW]
│       ├── vehicle_information_screen.dart [NEW]
│       ├── driver_home_screen.dart [UPDATED]
│       └── driver_profile_screen.dart [UPDATED]
└── main.dart [UPDATED]
```

## Important Notes

1. **Auto-Refresh:** Status automatically refreshes after upload/delete/update
2. **Real-time UI:** Uses Provider for reactive updates
3. **Error Handling:** All edge cases covered with user-friendly messages
4. **File Validation:** Size (10MB) and format checked before upload
5. **Navigation:** Can access from profile OR when trying to go online
6. **Backwards Compatible:** Old methods still work, new ones preferred

---

**This flow ensures:**
- ✅ Drivers can't go online without completing profile
- ✅ Clear guidance on what's missing
- ✅ Easy access to upload screens
- ✅ Real-time status updates
- ✅ Proper error handling
