class BankDetails {
  final String? accountHolderName;
  final String? accountNumber;
  final String? sortCode;
  final String? accountType;
  final String? accountNumberMasked;

  BankDetails({
    this.accountHolderName,
    this.accountNumber,
    this.sortCode,
    this.accountType,
    this.accountNumberMasked,
  });

  factory BankDetails.fromJson(Map<String, dynamic> json) {
    return BankDetails(
      accountHolderName: json['accountHolderName'],
      accountNumber: json['accountNumber'],
      sortCode: json['sortCode'],
      accountType: json['accountType'],
      accountNumberMasked: json['accountNumberMasked'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    if (accountHolderName != null) data['accountHolderName'] = accountHolderName;
    if (accountNumber != null) data['accountNumber'] = accountNumber;
    if (sortCode != null) data['sortCode'] = sortCode;
    if (accountType != null) data['accountType'] = accountType;
    // accountNumberMasked is usually read-only from backend
    return data;
  }
}
