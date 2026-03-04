/// Document types for driver registration (Sections 1 & 2)
enum DocumentType {
  // Section 1: Driving License
  licenseFront('licenseFront', 'License Front', 'Section 1: Driving License'),
  licenseBack('licenseBack', 'License Back', 'Section 1: Driving License'),

  // Section 2: Vehicle Documents
  privateHireLicence('privateHireLicence', 'Private Hire Licence', 'Section 2: Vehicle Documents'),
  roadTax('roadTax', 'Road Tax', 'Section 2: Vehicle Documents'),
  mot('mot', 'MOT Certificate', 'Section 2: Vehicle Documents'),
  insurance('insurance', 'Insurance Certificate', 'Section 2: Vehicle Documents'),
  dbsCertificate('dbsCertificate', 'DBS Certificate', 'Section 2: Vehicle Documents');

  final String apiKey;
  final String displayName;
  final String section;

  const DocumentType(this.apiKey, this.displayName, this.section);

  /// Get all Section 1 documents (License)
  static List<DocumentType> get section1 => [licenseFront, licenseBack];

  /// Get all Section 2 documents (Vehicle)
  static List<DocumentType> get section2 => [privateHireLicence, roadTax, mot, insurance, dbsCertificate];

  /// Parse from API key string
  static DocumentType? fromApiKey(String key) {
    try {
      return DocumentType.values.firstWhere((type) => type.apiKey == key);
    } catch (e) {
      return null;
    }
  }
}

/// Model for a single document upload
class DriverDocument {
  final String url;
  final String type;
  final String originalName;
  final DateTime? uploadedAt;

  DriverDocument({
    required this.url,
    required this.type,
    required this.originalName,
    this.uploadedAt,
  });

  factory DriverDocument.fromJson(Map<String, dynamic> json) {
    return DriverDocument(
      url: json['url'] ?? '',
      type: json['type'] ?? '',
      originalName: json['originalName'] ?? json['name'] ?? '',
      uploadedAt: json['uploadedAt'] != null 
          ? DateTime.tryParse(json['uploadedAt']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'type': type,
      'originalName': originalName,
      if (uploadedAt != null) 'uploadedAt': uploadedAt!.toIso8601String(),
    };
  }
}

/// Model for driver profile status
class DriverProfileStatus {
  final bool isComplete;
  final String verificationStatus; // 'pending', 'approved', 'rejected'
  final bool canGoOnline;
  final Map<String, bool> missingItems;

  DriverProfileStatus({
    required this.isComplete,
    required this.verificationStatus,
    required this.canGoOnline,
    required this.missingItems,
  });

  factory DriverProfileStatus.fromJson(Map<String, dynamic> json) {
    final missingItemsData = json['missingItems'] as Map<String, dynamic>? ?? {};
    final missingItems = <String, bool>{};
    
    // Convert all values to bool
    missingItemsData.forEach((key, value) {
      missingItems[key] = value == true;
    });

    return DriverProfileStatus(
      isComplete: json['isComplete'] == true,
      verificationStatus: json['verificationStatus']?.toString() ?? 'pending',
      canGoOnline: json['canGoOnline'] == true,
      missingItems: missingItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isComplete': isComplete,
      'verificationStatus': verificationStatus,
      'canGoOnline': canGoOnline,
      'missingItems': missingItems,
    };
  }

  /// Check if a specific document is missing
  bool isDocumentMissing(DocumentType type) {
    return missingItems[type.apiKey] == true;
  }

  /// Get count of missing documents
  int get missingDocumentCount {
    return missingItems.values.where((isMissing) => isMissing == true).length;
  }

  /// Check if bank details are missing
  bool get isBankDetailsMissing => missingItems['bankDetails'] == true;

  /// Get list of missing document types
  List<DocumentType> getMissingDocumentTypes() {
    final missing = <DocumentType>[];
    for (var type in DocumentType.values) {
      if (isDocumentMissing(type)) {
        missing.add(type);
      }
    }
    return missing;
  }

  /// Check if all Section 1 documents are uploaded
  bool get isSection1Complete {
    return DocumentType.section1.every((type) => !isDocumentMissing(type));
  }

  /// Check if all Section 2 documents are uploaded
  bool get isSection2Complete {
    return DocumentType.section2.every((type) => !isDocumentMissing(type));
  }

  /// Get verification status display text
  String get verificationStatusText {
    switch (verificationStatus.toLowerCase()) {
      case 'approved':
        return 'Approved';
      case 'pending':
        return 'Pending Review';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Unknown';
    }
  }
}
