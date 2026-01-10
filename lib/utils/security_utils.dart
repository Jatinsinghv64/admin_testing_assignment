// lib/utils/security_utils.dart
// ================================
// SECURITY UTILITIES
// ================================
// Centralized input validation, sanitization, and security utilities.
// Implements OWASP best practices for input handling.

/// ================================
/// INPUT LENGTH LIMITS
/// ================================
/// Maximum allowed lengths for various input types.
/// Prevents denial-of-service attacks and database bloat.
class InputLimits {
  // User identity
  static const int maxEmail = 254; // RFC 5321 limit
  static const int maxPhoneNumber = 20;
  static const int maxName = 100;
  static const int maxPassword = 128;

  // Order-related
  static const int maxOrderNotes = 500;
  static const int maxCancellationReason = 500;
  static const int maxSpecialInstructions = 500;
  static const int maxAddress = 500;

  // Menu/Product
  static const int maxMenuItemName = 100;
  static const int maxMenuItemDescription = 1000;
  static const int maxCategoryName = 50;
  static const int maxCouponCode = 20;

  // IDs
  static const int maxDocumentId = 128;
  static const int maxBranchId = 50;
  static const int maxOrderId = 50;

  // Prices (in currency units)
  static const double maxPrice = 99999.99;
  static const double minPrice = 0.0;
  static const double maxOrderTotal = 999999.99;

  // Quantity limits
  static const int maxQuantity = 100;
  static const int maxItemsPerOrder = 50;

  // General
  static const int maxGeneralText = 1000;
}

/// ================================
/// INPUT VALIDATION PATTERNS
/// ================================
/// Regular expressions for validating common input formats.
/// All patterns are compiled once for performance.
class ValidationPatterns {
  // Email: RFC 5322 simplified pattern
  static final RegExp email = RegExp(
    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$',
    caseSensitive: false,
  );

  // Phone: International format, 8-20 digits with optional + prefix
  static final RegExp phone = RegExp(r'^\+?[0-9]{8,20}$');

  // Document IDs: Alphanumeric with hyphens and underscores
  static final RegExp documentId = RegExp(r'^[A-Za-z0-9_-]+$');

  // Order number format: PREFIX-YYMMDD-NNN
  static final RegExp orderNumber = RegExp(r'^[A-Z]{2,4}-\d{6}-\d{3,4}$');

  // Branch ID: Alphanumeric
  static final RegExp branchId = RegExp(r'^[A-Za-z0-9_-]+$');

  // Coupon code: Alphanumeric and common symbols
  static final RegExp couponCode = RegExp(r'^[A-Za-z0-9_-]+$');

  // Price: Up to 2 decimal places
  static final RegExp price = RegExp(r'^\d+(\.\d{1,2})?$');

  // Name: Letters, spaces, hyphens, apostrophes (multi-language support)
  static final RegExp name = RegExp(r"^[\p{L}\p{M}\s\-'\.]+$", unicode: true);

  // URL: Basic URL validation
  static final RegExp url = RegExp(
    r'^https?:\/\/[a-zA-Z0-9][-a-zA-Z0-9]*(\.[a-zA-Z0-9][-a-zA-Z0-9]*)+.*$',
    caseSensitive: false,
  );

  // Firebase Storage URL
  static final RegExp firebaseStorageUrl = RegExp(
    r'^https:\/\/firebasestorage\.googleapis\.com\/.*$',
    caseSensitive: false,
  );

  // No script tags or HTML (security)
  static final RegExp noHtmlTags = RegExp(r'<[^>]*>');

  // No SQL injection patterns
  static final RegExp sqlInjection = RegExp(
    r"(\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|ALTER|CREATE|TRUNCATE)\b)|(--)|(;)|(\bOR\b\s+\d+\s*=\s*\d+)|(\bAND\b\s+\d+\s*=\s*\d+)",
    caseSensitive: false,
  );

  // No NoSQL injection patterns (for Firestore)
  static final RegExp noSqlInjection = RegExp(
    r'\$where|\$regex|\$gt|\$gte|\$lt|\$lte|\$ne|\$nin|\$or|\$and',
    caseSensitive: false,
  );
}

/// ================================
/// INPUT VALIDATOR
/// ================================
/// Static methods for validating user inputs.
/// Returns null if valid, or an error message if invalid.
class InputValidator {
  /// Validates email format and length.
  static String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final email = value.trim();

    if (email.length > InputLimits.maxEmail) {
      return 'Email is too long (max ${InputLimits.maxEmail} characters)';
    }

    if (!ValidationPatterns.email.hasMatch(email)) {
      return 'Please enter a valid email address';
    }

    return null; // Valid
  }

  /// Validates phone number format.
  static String? validatePhone(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Phone number is required' : null;
    }

    final phone = value.trim().replaceAll(RegExp(r'\s+'), '');

    if (phone.length > InputLimits.maxPhoneNumber) {
      return 'Phone number is too long';
    }

    if (!ValidationPatterns.phone.hasMatch(phone)) {
      return 'Please enter a valid phone number';
    }

    return null; // Valid
  }

  /// Validates a name field (person, item, etc.).
  static String? validateName(String? value, {
    bool required = true,
    int maxLength = 100,
    String fieldName = 'Name',
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? '$fieldName is required' : null;
    }

    final name = value.trim();

    if (name.length > maxLength) {
      return '$fieldName is too long (max $maxLength characters)';
    }

    if (name.length < 2) {
      return '$fieldName must be at least 2 characters';
    }

    // Check for potential injection attacks
    if (_containsInjectionPatterns(name)) {
      return '$fieldName contains invalid characters';
    }

    return null; // Valid
  }

  /// Validates a document ID (Firestore document ID, order ID, etc.).
  static String? validateDocumentId(String? value, {
    bool required = true,
    String fieldName = 'ID',
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? '$fieldName is required' : null;
    }

    final id = value.trim();

    if (id.length > InputLimits.maxDocumentId) {
      return '$fieldName is too long';
    }

    if (!ValidationPatterns.documentId.hasMatch(id)) {
      return '$fieldName contains invalid characters';
    }

    return null; // Valid
  }

  /// Validates price input.
  static String? validatePrice(String? value, {
    bool required = true,
    double minValue = 0.0,
    double? maxValue,
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Price is required' : null;
    }

    final price = double.tryParse(value.trim());

    if (price == null) {
      return 'Please enter a valid number';
    }

    if (price < minValue) {
      return 'Price cannot be negative';
    }

    final max = maxValue ?? InputLimits.maxPrice;
    if (price > max) {
      return 'Price exceeds maximum allowed ($max)';
    }

    return null; // Valid
  }

  /// Validates quantity input.
  static String? validateQuantity(String? value, {
    bool required = true,
    int minValue = 1,
    int? maxValue,
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Quantity is required' : null;
    }

    final quantity = int.tryParse(value.trim());

    if (quantity == null) {
      return 'Please enter a valid number';
    }

    if (quantity < minValue) {
      return 'Quantity must be at least $minValue';
    }

    final max = maxValue ?? InputLimits.maxQuantity;
    if (quantity > max) {
      return 'Quantity cannot exceed $max';
    }

    return null; // Valid
  }

  /// Validates general text input with length limit.
  static String? validateText(String? value, {
    bool required = false,
    int maxLength = 1000,
    String fieldName = 'Text',
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? '$fieldName is required' : null;
    }

    final text = value.trim();

    if (text.length > maxLength) {
      return '$fieldName is too long (max $maxLength characters)';
    }

    // Check for potential injection attacks
    if (_containsInjectionPatterns(text)) {
      return '$fieldName contains potentially harmful content';
    }

    return null; // Valid
  }

  /// Validates URL format.
  static String? validateUrl(String? value, {
    bool required = false,
    bool requireHttps = true,
  }) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'URL is required' : null;
    }

    final url = value.trim();

    if (url.length > 2000) {
      return 'URL is too long';
    }

    if (requireHttps && !url.startsWith('https://')) {
      return 'URL must use HTTPS';
    }

    if (!ValidationPatterns.url.hasMatch(url)) {
      return 'Please enter a valid URL';
    }

    return null; // Valid
  }

  /// Validates coupon code format.
  static String? validateCouponCode(String? value, {bool required = true}) {
    if (value == null || value.trim().isEmpty) {
      return required ? 'Coupon code is required' : null;
    }

    final code = value.trim().toUpperCase();

    if (code.length > InputLimits.maxCouponCode) {
      return 'Coupon code is too long';
    }

    if (code.length < 3) {
      return 'Coupon code must be at least 3 characters';
    }

    if (!ValidationPatterns.couponCode.hasMatch(code)) {
      return 'Coupon code contains invalid characters';
    }

    return null; // Valid
  }

  /// Checks if input contains potential injection attacks.
  static bool _containsInjectionPatterns(String input) {
    // Check for HTML/script tags
    if (ValidationPatterns.noHtmlTags.hasMatch(input)) {
      return true;
    }

    // Check for SQL injection
    if (ValidationPatterns.sqlInjection.hasMatch(input)) {
      return true;
    }

    // Check for NoSQL injection
    if (ValidationPatterns.noSqlInjection.hasMatch(input)) {
      return true;
    }

    return false;
  }
}

/// ================================
/// INPUT SANITIZER
/// ================================
/// Methods for sanitizing user input before storage.
class InputSanitizer {
  /// Sanitizes text input by removing potentially harmful content.
  /// Use this for free-form text fields that will be stored/displayed.
  static String sanitizeText(String? input) {
    if (input == null || input.isEmpty) return '';

    String sanitized = input;

    // Trim whitespace
    sanitized = sanitized.trim();

    // Remove HTML tags
    sanitized = sanitized.replaceAll(ValidationPatterns.noHtmlTags, '');

    // Normalize whitespace (collapse multiple spaces/newlines)
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');

    // Remove null bytes and other control characters
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    return sanitized;
  }

  /// Sanitizes and normalizes email input.
  static String sanitizeEmail(String? input) {
    if (input == null || input.isEmpty) return '';

    // Trim and lowercase
    return input.trim().toLowerCase();
  }

  /// Sanitizes phone number input.
  static String sanitizePhone(String? input) {
    if (input == null || input.isEmpty) return '';

    // Remove all non-digit characters except + at the start
    String sanitized = input.trim();
    if (sanitized.startsWith('+')) {
      sanitized = '+${sanitized.substring(1).replaceAll(RegExp(r'[^\d]'), '')}';
    } else {
      sanitized = sanitized.replaceAll(RegExp(r'[^\d]'), '');
    }

    return sanitized;
  }

  /// Sanitizes a document ID.
  static String sanitizeDocumentId(String? input) {
    if (input == null || input.isEmpty) return '';

    // Only allow alphanumeric, hyphens, underscores
    return input.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  }

  /// Sanitizes price input and returns as double.
  static double? sanitizePrice(String? input) {
    if (input == null || input.isEmpty) return null;

    // Remove currency symbols and spaces
    final cleaned = input.trim().replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned);
  }

  /// Sanitizes a URL by encoding special characters.
  static String sanitizeUrl(String? input) {
    if (input == null || input.isEmpty) return '';

    return Uri.encodeFull(input.trim());
  }

  /// Sanitizes notes/comments fields.
  /// Allows newlines but removes other problematic content.
  static String sanitizeNotes(String? input) {
    if (input == null || input.isEmpty) return '';

    String sanitized = input;

    // Remove HTML tags
    sanitized = sanitized.replaceAll(ValidationPatterns.noHtmlTags, '');

    // Remove null bytes and other control characters (except newline, tab)
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    // Trim and limit consecutive newlines
    sanitized = sanitized.trim().replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return sanitized;
  }
}

/// ================================
/// ORDER DATA VALIDATOR
/// ================================
/// Schema-based validation for order data.
/// Use before writing to Firestore.
class OrderDataValidator {
  /// Validates order data before creation/update.
  /// Returns null if valid, or list of error messages if invalid.
  static List<String>? validateOrderData(Map<String, dynamic> data, {
    bool isUpdate = false,
  }) {
    final errors = <String>[];

    // Required fields for new orders
    if (!isUpdate) {
      if (!data.containsKey('status') || data['status'] == null) {
        errors.add('Order status is required');
      }
      if (!data.containsKey('timestamp')) {
        errors.add('Order timestamp is required');
      }
    }

    // Validate status if present
    if (data.containsKey('status')) {
      final status = data['status'];
      if (status is! String || status.isEmpty) {
        errors.add('Invalid order status');
      } else if (status.length > 50) {
        errors.add('Status field is too long');
      }
    }

    // Validate totalAmount if present
    if (data.containsKey('totalAmount')) {
      final amount = data['totalAmount'];
      if (amount is! num) {
        errors.add('Total amount must be a number');
      } else if (amount < 0) {
        errors.add('Total amount cannot be negative');
      } else if (amount > InputLimits.maxOrderTotal) {
        errors.add('Total amount exceeds maximum');
      }
    }

    // Validate items if present
    if (data.containsKey('items')) {
      final items = data['items'];
      if (items is! List) {
        errors.add('Items must be a list');
      } else if (items.length > InputLimits.maxItemsPerOrder) {
        errors.add('Too many items in order (max ${InputLimits.maxItemsPerOrder})');
      }
    }

    // Validate notes if present
    if (data.containsKey('notes')) {
      final notes = data['notes'];
      if (notes is String && notes.length > InputLimits.maxOrderNotes) {
        errors.add('Order notes too long');
      }
    }

    // Validate cancellation reason if present
    if (data.containsKey('cancellationReason')) {
      final reason = data['cancellationReason'];
      if (reason is String && reason.length > InputLimits.maxCancellationReason) {
        errors.add('Cancellation reason too long');
      }
    }

    // Check for unexpected fields (NoSQL injection prevention)
    final allowedFields = {
      'status', 'timestamp', 'totalAmount', 'items', 'notes', 'branchId',
      'branchIds', 'customerId', 'customerName', 'customerPhone', 'customerEmail',
      'deliveryAddress', 'Order_type', 'orderType', 'paymentMethod', 'paymentStatus',
      'riderId', 'cancellationReason', 'cancelledBy', 'dailyOrderNumber',
      'orderSequence', 'timestamps', 'autoAssignStarted', 'assignmentNotes',
      'isExchange', 'originalOrderId', 'specialInstructions', 'tableNumber',
      'carPlateNumber', 'subTotal', 'deliveryFee', 'discount', 'tax',
      '_cloudFunctionUpdate', '_invalidTransitionLog', 'orderNumberAssignedAt',
      'orderNumberFallback', 'createdAt',
    };

    final unexpectedFields = data.keys.where((k) => !allowedFields.contains(k)).toList();
    if (unexpectedFields.isNotEmpty) {
      errors.add('Unexpected fields in order data: ${unexpectedFields.join(", ")}');
    }

    return errors.isEmpty ? null : errors;
  }
}

/// ================================
/// MENU ITEM DATA VALIDATOR
/// ================================
/// Schema-based validation for menu item data.
class MenuItemDataValidator {
  static List<String>? validateMenuItemData(Map<String, dynamic> data, {
    bool isUpdate = false,
  }) {
    final errors = <String>[];

    // Required fields for new items
    if (!isUpdate) {
      if (!data.containsKey('name') || (data['name'] as String?)?.isEmpty == true) {
        errors.add('Menu item name is required');
      }
      if (!data.containsKey('price')) {
        errors.add('Menu item price is required');
      }
    }

    // Validate name
    if (data.containsKey('name')) {
      final name = data['name'];
      if (name is! String || name.length > InputLimits.maxMenuItemName) {
        errors.add('Menu item name is too long');
      }
    }

    // Validate name_ar (Arabic name)
    if (data.containsKey('name_ar')) {
      final nameAr = data['name_ar'];
      if (nameAr is String && nameAr.length > InputLimits.maxMenuItemName) {
        errors.add('Arabic name is too long');
      }
    }

    // Validate description
    if (data.containsKey('description')) {
      final desc = data['description'];
      if (desc is String && desc.length > InputLimits.maxMenuItemDescription) {
        errors.add('Description is too long');
      }
    }

    // Validate price
    if (data.containsKey('price')) {
      final price = data['price'];
      if (price is! num) {
        errors.add('Price must be a number');
      } else if (price < 0) {
        errors.add('Price cannot be negative');
      } else if (price > InputLimits.maxPrice) {
        errors.add('Price exceeds maximum');
      }
    }

    // Validate imageUrl
    if (data.containsKey('imageUrl')) {
      final url = data['imageUrl'];
      if (url is String && url.isNotEmpty) {
        if (!ValidationPatterns.firebaseStorageUrl.hasMatch(url) &&
            !ValidationPatterns.url.hasMatch(url)) {
          errors.add('Invalid image URL');
        }
      }
    }

    return errors.isEmpty ? null : errors;
  }
}

/// ================================
/// STAFF DATA VALIDATOR
/// ================================
/// Schema-based validation for staff data.
class StaffDataValidator {
  /// Valid role values
  static const validRoles = {'super_admin', 'branch_admin', 'branchadmin', 'staff', 'manager'};

  static List<String>? validateStaffData(Map<String, dynamic> data, {
    bool isUpdate = false,
  }) {
    final errors = <String>[];

    // Validate email
    if (data.containsKey('email')) {
      final emailError = InputValidator.validateEmail(data['email'] as String?);
      if (emailError != null) {
        errors.add(emailError);
      }
    } else if (!isUpdate) {
      errors.add('Email is required');
    }

    // Validate role
    if (data.containsKey('role')) {
      final role = data['role'];
      if (role is! String || !validRoles.contains(role.toLowerCase())) {
        errors.add('Invalid role: $role');
      }
    }

    // Validate name
    if (data.containsKey('name')) {
      final nameError = InputValidator.validateName(
        data['name'] as String?,
        required: false,
        maxLength: InputLimits.maxName,
      );
      if (nameError != null) {
        errors.add(nameError);
      }
    }

    // Validate phone
    if (data.containsKey('phone')) {
      final phoneError = InputValidator.validatePhone(
        data['phone'] as String?,
        required: false,
      );
      if (phoneError != null) {
        errors.add(phoneError);
      }
    }

    // Validate branchIds
    if (data.containsKey('branchIds')) {
      final branchIds = data['branchIds'];
      if (branchIds is! List) {
        errors.add('branchIds must be a list');
      } else {
        for (final id in branchIds) {
          if (id is! String || id.length > InputLimits.maxBranchId) {
            errors.add('Invalid branch ID: $id');
            break;
          }
        }
      }
    }

    // Validate permissions
    if (data.containsKey('permissions')) {
      final permissions = data['permissions'];
      if (permissions is! Map) {
        errors.add('Permissions must be a map');
      }
    }

    return errors.isEmpty ? null : errors;
  }
}
