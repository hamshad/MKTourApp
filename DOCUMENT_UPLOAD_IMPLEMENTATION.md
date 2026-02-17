# Document Upload System Implementation Guide

## Overview
This implementation provides a complete document management system for driver registration, supporting both Section 1 (License) and Section 2 (Vehicle Documents) as per the API specifications.

## What Was Implemented

### 1. **API Constants** (`lib/core/constants/api_constants.dart`)
Added generic document endpoints:
- `uploadDocument(type)` - POST /api/v1/drivers/documents/:type
- `deleteDocument(type)` - DELETE /api/v1/drivers/documents/:type

### 2. **Document Models** (`lib/core/models/driver_document.dart`)
Created comprehensive models:
- **DocumentType enum**: All 6 document types
  - Section 1: `licenseFront`, `licenseBack`
  - Section 2: `privateHireLicence`, `roadTax`, `mot`, `insurance`
- **DriverDocument class**: Represents uploaded documents
- **DriverProfileStatus class**: Complete profile status with validation

### 3. **API Service** (`lib/core/api_service.dart`)
Added two new methods:
- `uploadDocument(String documentType, File document)` - Generic upload for all document types
- `deleteDocument(String documentType)` - Generic delete for any document

Features:
- Supports multiple file formats (PDF, DOC, DOCX, JPG, PNG, HEIC)
- Automatic MIME type detection
- Proper error handling with 401 unauthorized checks

### 4. **Auth Provider** (`lib/core/auth_provider.dart`)
Added three new methods:
- `uploadDocument(String documentType, File document)` - Upload with status refresh
- `deleteDocument(String documentType)` - Delete with status refresh
- `updateVehicleInformation()` - Update vehicle details (categorySlug, model, number, color)

All methods automatically refresh the profile status after operations.

### 5. **Document Checklist Screen** (`lib/features/driver/document_checklist_screen.dart`)
Full-featured document management UI with:
- **Status Card**: Shows approval status, pending review, or missing items count
- **Section 1 & 2 Lists**: All 6 documents organized by section
- **Upload Options**: Camera, Gallery, or File picker
- **Visual Indicators**: Green checkmarks for uploaded, red warnings for missing
- **Missing Count Badge**: Shows how many documents are pending
- **File Validation**: 10MB size limit, format checking
- **Pull-to-Refresh**: Manual status refresh
- **Info Card**: User instructions and requirements

### 6. **Enhanced Go-Online Logic** (`lib/features/driver/driver_home_screen.dart`)
Updated `_toggleOnline()` method to handle:
- **PROFILE_INCOMPLETE Error (403)**: Shows dialog with "Complete Profile" button
- **NOT_APPROVED Error (403)**: Shows pending approval dialog
- **Navigation**: Both dialogs allow navigation to Document Checklist screen

Added two dialog methods:
- `_showProfileIncompleteDialog()` - Guides user to upload missing documents
- `_showNotApprovedDialog()` - Informs user to wait for admin approval

### 7. **Profile Screen Integration** (`lib/features/driver/driver_profile_screen.dart`)
Added menu item for Document Checklist:
- Icon: Checklist symbol
- Badge: Shows missing document count or "Complete" status
- Navigation: Direct link to document checklist

### 8. **App Routing** (`lib/main.dart`)
Added route:
```dart
'/driver/documents': (context) => const DocumentChecklistScreen()
```

## Usage Flow

### For Drivers:
1. **Navigate to Documents**:
   - From Driver Profile → "Document Checklist"
   - Or when trying to go online with incomplete profile

2. **Upload Documents**:
   - Tap upload icon on any missing document
   - Choose: Camera, Gallery, or Files
   - File is validated and uploaded automatically
   - Status refreshes immediately

3. **Replace Documents**:
   - Tap refresh icon on uploaded documents
   - Old file is automatically deleted, new one uploaded

4. **Delete Documents**:
   - Tap delete icon (red trash)
   - Confirm deletion
   - Status updates immediately

5. **Go Online**:
   - Once all documents uploaded and approved
   - `canGoOnline` flag becomes `true`
   - Driver can activate online status

### API Response Handling:

#### Upload Success:
```json
{
  "success": true,
  "message": "license front uploaded successfully",
  "data": {
    "document": {
      "url": "https://res.cloudinary.com/...",
      "type": "licenseFront",
      "originalName": "my_license_photo.heic"
    }
  }
}
```

#### Profile Status:
```json
{
  "success": true,
  "data": {
    "profileStatus": {
      "isComplete": false,
      "verificationStatus": "pending",
      "canGoOnline": false,
      "missingItems": {
        "licenseFront": true,    // Missing
        "licenseBack": false,     // Uploaded
        "privateHireLicence": true,
        "roadTax": true,
        "mot": true,
        "insurance": false,      // Uploaded
        "vehicleImages": false,
        "vehicleDetails": false
      }
    }
  }
}
```

#### Go Online Error (Profile Incomplete):
```json
{
  "success": false,
  "code": "PROFILE_INCOMPLETE",
  "message": "Please complete your profile by uploading all required documents"
}
```

#### Go Online Error (Not Approved):
```json
{
  "success": false,
  "code": "NOT_APPROVED",
  "message": "Your account is pending admin approval"
}
```

## File Upload Specifications

### Supported Formats:
- **Images**: JPG, JPEG, PNG, HEIC
- **Documents**: PDF, DOC, DOCX

### Size Limits:
- Maximum: 10MB per file (configurable in `document_checklist_screen.dart`)
- API limit: As specified by backend

### Field Name:
All uploads use the `document` field name in multipart/form-data

## Code Examples

### Upload a Document:
```dart
final auth = Provider.of<AuthProvider>(context, listen: false);
final file = File('/path/to/license.pdf');

try {
  final response = await auth.uploadDocument('licenseFront', file);
  if (response['success'] == true) {
    // Upload successful, status automatically refreshed
    print('Document uploaded: ${response['data']}');
  }
} catch (e) {
  print('Upload failed: $e');
}
```

### Check Profile Status:
```dart
final auth = Provider.of<AuthProvider>(context, listen: false);
await auth.fetchDriverProfileStatus();

final statusData = auth.driverProfileStatus;
final profileStatus = DriverProfileStatus.fromJson(statusData);

if (profileStatus.canGoOnline) {
  // Driver can go online
} else if (profileStatus.isComplete) {
  // Complete but pending approval
} else {
  // Missing documents: ${profileStatus.missingDocumentCount}
  final missingDocs = profileStatus.getMissingDocumentTypes();
}
```

### Update Vehicle Information:
```dart
final auth = Provider.of<AuthProvider>(context, listen: false);

await auth.updateVehicleInformation(
  categorySlug: 'luxury-sedan',
  model: 'Toyota Prius 2022',
  number: 'AB12 CDE',
  color: 'Black',
);
```

## Error Handling

The system handles several error scenarios:

1. **File Too Large**: Shows snackbar, prevents upload
2. **Network Error**: Caught and displayed to user
3. **401 Unauthorized**: Triggers logout (handled globally)
4. **403 Profile Incomplete**: Shows dialog with navigation
5. **403 Not Approved**: Shows pending approval message
6. **Upload Failed**: Shows error message from API

## UI Features

### Status Card Colors:
- **Green**: Approved and can go online
- **Orange**: Complete but pending approval
- **Red**: Profile rejected
- **Blue**: Incomplete profile

### Document List:
- **Green checkmark**: Document uploaded
- **Red error icon**: Document missing
- **Upload icon**: Click to upload
- **Refresh icon**: Click to replace
- **Delete icon**: Click to remove

### Loading States:
- Spinner on initial load
- Individual spinner per document during upload/delete
- Pull-to-refresh indicator

## Testing Checklist

- [ ] Upload all 6 document types
- [ ] Replace an existing document
- [ ] Delete a document
- [ ] Try to go online with incomplete profile
- [ ] Try to go online when pending approval
- [ ] Check status updates after each operation
- [ ] Test with different file formats (PDF, JPG, PNG)
- [ ] Test with file > 10MB (should fail)
- [ ] Test with slow network (should show loading)
- [ ] Test profile status badge in profile screen

## Future Enhancements

Potential additions:
1. Document preview/view functionality
2. Rejection reasons from admin
3. Resubmission after rejection
4. Document expiry date tracking
5. Push notifications for approval/rejection
6. OCR for automatic form filling
7. Document validation (e.g., date checks)
8. Bulk upload option

## Notes

- All document operations automatically trigger a profile status refresh
- The old license upload methods (`uploadDriverLicense`, etc.) are still available but can be deprecated
- Vehicle information must be updated via the `updateVehicleInformation` method
- The system uses `Provider` for state management with automatic UI updates
- File picker permissions must be configured in Android/iOS manifests
