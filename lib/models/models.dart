// نسخة Dart من types.ts — نفس أسماء الحقول بالظبط عشان تشتغل على نفس
// قاعدة بيانات Firestore بتاعة نسخة الويب من غير أي تغيير.
import 'package:cloud_firestore/cloud_firestore.dart';

/// تحويل أي قيمة وقت (Timestamp أو رقم) إلى milliseconds
/// (نفس دور stripFirestore في نسخة الويب).
int? toMillis(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is num) return v.toInt();
  return null;
}

double _d(dynamic v, [double def = 0]) => v is num ? v.toDouble() : def;
int _i(dynamic v, [int def = 0]) => v is num ? v.toInt() : def;
String _s(dynamic v, [String def = '']) => v is String ? v : def;

/// يشيل القيم الـ null ويحول Timestamp إلى millis (مكافئ stripFirestore).
dynamic stripFirestore(dynamic data) {
  if (data == null) return null;
  if (data is Timestamp) return data.millisecondsSinceEpoch;
  if (data is DocumentReference) return data.path;
  if (data is Map) {
    final out = <String, dynamic>{};
    data.forEach((k, v) {
      final key = k.toString();
      if (key.startsWith('_') || key.startsWith(r'$')) return;
      final cleaned = stripFirestore(v);
      if (cleaned != null) out[key] = cleaned;
    });
    return out;
  }
  if (data is List) {
    return data.map(stripFirestore).where((e) => e != null).toList();
  }
  return data;
}

// ───────────────────────── Enums (قيمها نصوص Firestore) ─────────────────────

enum UserRole {
  admin('ADMIN'),
  operator('OPERATOR'),
  driver('DRIVER'),
  customer('CUSTOMER'),
  unknown('');

  final String value;
  const UserRole(this.value);
  static UserRole parse(String? s) => values.firstWhere((e) => e.value == s,
      orElse: () => UserRole.unknown);
}

enum UserStatus {
  approved('APPROVED'),
  suspended('SUSPENDED');

  final String value;
  const UserStatus(this.value);
  // أي قيمة قديمة (زي PENDING_APPROVAL) بتتعامل كحساب مفعّل: مفيش تفعيل من الأدمن.
  static UserStatus parse(String? s) => values
      .firstWhere((e) => e.value == s, orElse: () => UserStatus.approved);
}

enum PaymentMethod {
  cash('CASH'),
  wallet('WALLET');

  final String value;
  const PaymentMethod(this.value);
  static PaymentMethod parse(String? s) => values
      .firstWhere((e) => e.value == s, orElse: () => PaymentMethod.cash);
}

enum VehicleType {
  toktok('TOKTOK'),
  motorcycle('MOTORCYCLE'),
  car('CAR');

  final String value;
  const VehicleType(this.value);
  static VehicleType parse(String? s) => values
      .firstWhere((e) => e.value == s, orElse: () => VehicleType.toktok);
  static VehicleType? tryParse(String? s) {
    for (final e in values) {
      if (e.value == s) return e;
    }
    return null;
  }
}

enum OrderCategory {
  taxi('TAXI'),
  food('FOOD'),
  pharmacy('PHARMACY'),
  grocery('GROCERY'),
  parcel('PARCEL');

  final String value;
  const OrderCategory(this.value);
  static OrderCategory parse(String? s) => values
      .firstWhere((e) => e.value == s, orElse: () => OrderCategory.taxi);
  static OrderCategory? tryParse(String? s) {
    for (final e in values) {
      if (e.value == s) return e;
    }
    return null;
  }
}

enum OrderStatus {
  draft('DRAFT'),
  pending('PENDING'),
  assigned('ASSIGNED'),
  picked('PICKED'),
  inDelivery('IN_DELIVERY'),
  delivered('DELIVERED'),
  cancelled('CANCELLED');

  final String value;
  const OrderStatus(this.value);
  String get labelAr {
    switch (this) {
      case OrderStatus.draft:
        return 'مسودة';
      case OrderStatus.pending:
        return 'بانتظار عروض الكباتن';
      case OrderStatus.assigned:
        return 'الكابتن في الطريق للاستلام';
      case OrderStatus.picked:
        return 'تم استلام الطلب - في الطريق إليك';
      case OrderStatus.inDelivery:
        return 'جاري التوصيل';
      case OrderStatus.delivered:
        return 'تم التسليم';
      case OrderStatus.cancelled:
        return 'ملغي';
    }
  }

  static OrderStatus parse(String? s) => values
      .firstWhere((e) => e.value == s, orElse: () => OrderStatus.pending);
}

// ───────────────────────── Models ─────────────────────────

class StatusHistoryItem {
  final OrderStatus status;
  final int changedAt;
  final String changedBy;
  const StatusHistoryItem(
      {required this.status, required this.changedAt, required this.changedBy});

  factory StatusHistoryItem.fromMap(Map<String, dynamic> m) =>
      StatusHistoryItem(
        status: OrderStatus.parse(m['status'] as String?),
        changedAt: toMillis(m['changedAt']) ?? 0,
        changedBy: _s(m['changedBy']),
      );

  Map<String, dynamic> toMap() =>
      {'status': status.value, 'changedAt': changedAt, 'changedBy': changedBy};
}

class Courier {
  final String id;
  final String userId;
  final bool isActive;
  final int currentOrdersCount;
  const Courier(
      {required this.id,
      required this.userId,
      required this.isActive,
      required this.currentOrdersCount});

  factory Courier.fromMap(Map<String, dynamic> m, [String? docId]) => Courier(
        id: _s(m['id'], docId ?? ''),
        userId: _s(m['userId']),
        isActive: m['isActive'] == true,
        currentOrdersCount: _i(m['currentOrdersCount']),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'userId': userId,
        'isActive': isActive,
        'currentOrdersCount': currentOrdersCount,
      };
}

class Ad {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String ctaText;
  final String type; // special_offer | restaurant | service | general
  final String? targetId;
  final OrderCategory? targetCategory;
  final String? whatsappNumber;
  final bool isActive;
  final int displayOrder;
  final int views;
  final int clicks;
  final int createdAt;

  const Ad({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.ctaText,
    required this.type,
    this.targetId,
    this.targetCategory,
    this.whatsappNumber,
    required this.isActive,
    required this.displayOrder,
    required this.views,
    required this.clicks,
    required this.createdAt,
  });

  factory Ad.fromMap(Map<String, dynamic> m, [String? docId]) => Ad(
        id: _s(m['id'], docId ?? ''),
        title: _s(m['title']),
        description: _s(m['description']),
        imageUrl: _s(m['imageUrl']),
        ctaText: _s(m['ctaText']),
        type: _s(m['type'], 'general'),
        targetId: m['targetId'] as String?,
        targetCategory: OrderCategory.tryParse(m['targetCategory'] as String?),
        whatsappNumber: m['whatsappNumber'] as String?,
        isActive: m['isActive'] == true,
        displayOrder: _i(m['displayOrder']),
        views: _i(m['views']),
        clicks: _i(m['clicks']),
        createdAt: toMillis(m['createdAt']) ?? 0,
      );

  Map<String, dynamic> toMap() => stripFirestore({
        'id': id,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'ctaText': ctaText,
        'type': type,
        'targetId': targetId,
        'targetCategory': targetCategory?.value,
        'whatsappNumber': whatsappNumber,
        'isActive': isActive,
        'displayOrder': displayOrder,
        'views': views,
        'clicks': clicks,
        'createdAt': createdAt,
      }) as Map<String, dynamic>;
}

class MenuItem {
  final String id;
  final String name;
  final double price;
  final String? description;
  final String? photoURL;
  const MenuItem(
      {required this.id,
      required this.name,
      required this.price,
      this.description,
      this.photoURL});

  factory MenuItem.fromMap(Map<String, dynamic> m) => MenuItem(
        id: _s(m['id']),
        name: _s(m['name']),
        price: _d(m['price']),
        description: m['description'] as String?,
        photoURL: m['photoURL'] as String?,
      );

  Map<String, dynamic> toMap() => stripFirestore({
        'id': id,
        'name': name,
        'price': price,
        'description': description,
        'photoURL': photoURL,
      }) as Map<String, dynamic>;
}

class Restaurant {
  final String id;
  final String name;
  final String category;
  final String address;
  final double lat;
  final double lng;
  final String? photoURL;
  final String? menuImageURL;
  final List<String>? menuImageURLs;
  final List<MenuItem> menu;
  final bool isOpen;
  final bool? isFeatured;
  final String? promoText;

  const Restaurant({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.lat,
    required this.lng,
    this.photoURL,
    this.menuImageURL,
    this.menuImageURLs,
    required this.menu,
    required this.isOpen,
    this.isFeatured,
    this.promoText,
  });

  factory Restaurant.fromMap(Map<String, dynamic> m, [String? docId]) =>
      Restaurant(
        id: _s(m['id'], docId ?? ''),
        name: _s(m['name']),
        category: _s(m['category']),
        address: _s(m['address']),
        lat: _d(m['lat']),
        lng: _d(m['lng']),
        photoURL: m['photoURL'] as String?,
        menuImageURL: m['menuImageURL'] as String?,
        menuImageURLs: (m['menuImageURLs'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        menu: ((m['menu'] as List?) ?? [])
            .map((e) => MenuItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        isOpen: m['isOpen'] == true,
        isFeatured: m['isFeatured'] as bool?,
        promoText: m['promoText'] as String?,
      );

  Map<String, dynamic> toMap() => stripFirestore({
        'id': id,
        'name': name,
        'category': category,
        'address': address,
        'lat': lat,
        'lng': lng,
        'photoURL': photoURL,
        'menuImageURL': menuImageURL,
        'menuImageURLs': menuImageURLs,
        'menu': menu.map((e) => e.toMap()).toList(),
        'isOpen': isOpen,
        'isFeatured': isFeatured,
        'promoText': promoText,
      }) as Map<String, dynamic>;
}

class CartItem {
  final String id;
  final String name;
  final double price;
  final int quantity;
  const CartItem(
      {required this.id,
      required this.name,
      required this.price,
      required this.quantity});

  CartItem copyWith({int? quantity}) => CartItem(
      id: id, name: name, price: price, quantity: quantity ?? this.quantity);

  factory CartItem.fromMap(Map<String, dynamic> m) => CartItem(
        id: _s(m['id']),
        name: _s(m['name']),
        price: _d(m['price']),
        quantity: _i(m['quantity']),
      );

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'price': price, 'quantity': quantity};
}

class Offer {
  final String id;
  final String orderId;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final double driverRating;
  final String? driverPhoto;
  final VehicleType vehicleType;
  final double price;
  final int createdAt;
  const Offer({
    required this.id,
    required this.orderId,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.driverRating,
    this.driverPhoto,
    required this.vehicleType,
    required this.price,
    required this.createdAt,
  });

  factory Offer.fromMap(Map<String, dynamic> m, [String? docId]) => Offer(
        id: _s(m['id'], docId ?? ''),
        orderId: _s(m['orderId']),
        driverId: _s(m['driverId']),
        driverName: _s(m['driverName']),
        driverPhone: _s(m['driverPhone']),
        driverRating: _d(m['driverRating']),
        driverPhoto: m['driverPhoto'] as String?,
        vehicleType: VehicleType.parse(m['vehicleType'] as String?),
        price: _d(m['price']),
        createdAt: toMillis(m['createdAt']) ?? 0,
      );

  Map<String, dynamic> toMap() => stripFirestore({
        'id': id,
        'orderId': orderId,
        'driverId': driverId,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'driverRating': driverRating,
        'driverPhoto': driverPhoto,
        'vehicleType': vehicleType.value,
        'price': price,
        'createdAt': createdAt,
      }) as Map<String, dynamic>;
}

class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint(this.lat, this.lng);
  factory LatLngPoint.fromMap(Map? m) =>
      LatLngPoint(_d(m?['lat']), _d(m?['lng']));
  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng};
}

class Village {
  final String id;
  final String name;
  final LatLngPoint center;
  const Village({required this.id, required this.name, required this.center});

  factory Village.fromMap(Map<String, dynamic> m) => Village(
        id: _s(m['id']),
        name: _s(m['name']),
        center: LatLngPoint.fromMap(m['center'] as Map?),
      );
  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'center': center.toMap()};
}

class District {
  final String id;
  final String name;
  final List<Village> villages;
  const District(
      {required this.id, required this.name, required this.villages});

  factory District.fromMap(Map<String, dynamic> m) => District(
        id: _s(m['id']),
        name: _s(m['name']),
        villages: ((m['villages'] as List?) ?? [])
            .map((e) => Village.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'villages': villages.map((e) => e.toMap()).toList(),
      };
}

class Pricing {
  final double basePrice;
  final double pricePerKm;
  final double minPrice;
  final double maxPrice;
  final double sameVillagePrice;
  final Map<VehicleType, double> multipliers;
  const Pricing({
    required this.basePrice,
    required this.pricePerKm,
    required this.minPrice,
    required this.maxPrice,
    required this.sameVillagePrice,
    required this.multipliers,
  });

  factory Pricing.fromMap(Map? m) {
    final mult = (m?['multipliers'] as Map?) ?? {};
    return Pricing(
      basePrice: _d(m?['basePrice']),
      pricePerKm: _d(m?['pricePerKm']),
      minPrice: _d(m?['minPrice']),
      maxPrice: _d(m?['maxPrice']),
      sameVillagePrice: _d(m?['sameVillagePrice']),
      multipliers: {
        for (final v in VehicleType.values) v: _d(mult[v.value], 1.0),
      },
    );
  }

  Map<String, dynamic> toMap() => {
        'basePrice': basePrice,
        'pricePerKm': pricePerKm,
        'minPrice': minPrice,
        'maxPrice': maxPrice,
        'sameVillagePrice': sameVillagePrice,
        'multipliers': {
          for (final e in multipliers.entries) e.key.value: e.value,
        },
      };
}

class Zone {
  final String id;
  final String name;
  final String operatorId;
  final Pricing pricing;
  final LatLngPoint center;
  final List<Village>? villages;
  const Zone({
    required this.id,
    required this.name,
    required this.operatorId,
    required this.pricing,
    required this.center,
    this.villages,
  });

  factory Zone.fromMap(Map<String, dynamic> m, [String? docId]) => Zone(
        id: _s(m['id'], docId ?? ''),
        name: _s(m['name']),
        operatorId: _s(m['operatorId']),
        pricing: Pricing.fromMap(m['pricing'] as Map?),
        center: LatLngPoint.fromMap(m['center'] as Map?),
        villages: (m['villages'] as List?)
            ?.map((e) => Village.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  Map<String, dynamic> toMap() => stripFirestore({
        'id': id,
        'name': name,
        'operatorId': operatorId,
        'pricing': pricing.toMap(),
        'center': center.toMap(),
        'villages': villages?.map((e) => e.toMap()).toList(),
      }) as Map<String, dynamic>;
}

class OrderPlace {
  final String address;
  final double lat;
  final double lng;
  final String? villageName;
  const OrderPlace(
      {required this.address,
      required this.lat,
      required this.lng,
      this.villageName});

  factory OrderPlace.fromMap(Map? m) => OrderPlace(
        address: _s(m?['address']),
        lat: _d(m?['lat']),
        lng: _d(m?['lng']),
        villageName: m?['villageName'] as String?,
      );

  Map<String, dynamic> toMap() => stripFirestore({
        'address': address,
        'lat': lat,
        'lng': lng,
        'villageName': villageName,
      }) as Map<String, dynamic>;
}

class Order {
  final String id;
  final String customerId;
  final String customerPhone;
  final String? driverId;
  final String? driverName;
  final String? driverPhone;
  final String? driverPhoto;
  final double? driverRating;
  final String operatorId;
  final String zoneId;
  final OrderCategory category;
  final OrderPlace pickup;
  final OrderPlace dropoff;
  final OrderStatus status;
  final String? assignedTo;
  final List<StatusHistoryItem>? statusHistory;
  final int updatedAt;
  final double price;
  final double distance;
  final double commission;
  final double operatorCut;
  final double driverCut;
  final int createdAt;
  final int? acceptedAt;
  final int? deliveredAt;
  final int? cancelledAt;
  final int? ratedAt;
  final String? notes;
  final String? pickupNotes;
  final String? dropoffNotes;
  final int? passengerCount;
  final String? prescriptionImage;
  final PaymentMethod paymentMethod;
  final VehicleType requestedVehicleType;
  final String? transactionId;
  final double? rating;
  final String? feedback;
  final List<CartItem>? foodItems;
  final String? restaurantId;
  final String? restaurantName;
  final String? specialRequest;
  final bool customerReceived; // العميل أكد إنه استلم الطلب فعلاً
  final bool ratingSkipped; // العميل تخطى التقييم

  const Order({
    required this.id,
    required this.customerId,
    required this.customerPhone,
    this.driverId,
    this.driverName,
    this.driverPhone,
    this.driverPhoto,
    this.driverRating,
    required this.operatorId,
    required this.zoneId,
    required this.category,
    required this.pickup,
    required this.dropoff,
    required this.status,
    this.assignedTo,
    this.statusHistory,
    required this.updatedAt,
    required this.price,
    required this.distance,
    required this.commission,
    required this.operatorCut,
    required this.driverCut,
    required this.createdAt,
    this.acceptedAt,
    this.deliveredAt,
    this.cancelledAt,
    this.ratedAt,
    this.notes,
    this.pickupNotes,
    this.dropoffNotes,
    this.passengerCount,
    this.prescriptionImage,
    required this.paymentMethod,
    required this.requestedVehicleType,
    this.transactionId,
    this.rating,
    this.feedback,
    this.foodItems,
    this.restaurantId,
    this.restaurantName,
    this.specialRequest,
    this.customerReceived = false,
    this.ratingSkipped = false,
  });

  factory Order.fromMap(Map<String, dynamic> m, [String? docId]) => Order(
        id: _s(m['id'], docId ?? ''),
        customerId: _s(m['customerId']),
        customerPhone: _s(m['customerPhone']),
        driverId: m['driverId'] as String?,
        driverName: m['driverName'] as String?,
        driverPhone: m['driverPhone'] as String?,
        driverPhoto: m['driverPhoto'] as String?,
        driverRating: m['driverRating'] is num
            ? (m['driverRating'] as num).toDouble()
            : null,
        operatorId: _s(m['operatorId']),
        zoneId: _s(m['zoneId']),
        category: OrderCategory.parse(m['category'] as String?),
        pickup: OrderPlace.fromMap(m['pickup'] as Map?),
        dropoff: OrderPlace.fromMap(m['dropoff'] as Map?),
        status: OrderStatus.parse(m['status'] as String?),
        assignedTo: m['assignedTo'] as String?,
        statusHistory: (m['statusHistory'] as List?)
            ?.map((e) =>
                StatusHistoryItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        updatedAt: toMillis(m['updatedAt']) ?? 0,
        price: _d(m['price']),
        distance: _d(m['distance']),
        commission: _d(m['commission']),
        operatorCut: _d(m['operatorCut']),
        driverCut: _d(m['driverCut']),
        createdAt: toMillis(m['createdAt']) ?? 0,
        acceptedAt: toMillis(m['acceptedAt']),
        deliveredAt: toMillis(m['deliveredAt']),
        cancelledAt: toMillis(m['cancelledAt']),
        ratedAt: toMillis(m['ratedAt']),
        notes: m['notes'] as String?,
        pickupNotes: m['pickupNotes'] as String?,
        dropoffNotes: m['dropoffNotes'] as String?,
        passengerCount:
            m['passengerCount'] is num ? (m['passengerCount'] as num).toInt() : null,
        prescriptionImage: m['prescriptionImage'] as String?,
        paymentMethod: PaymentMethod.parse(m['paymentMethod'] as String?),
        requestedVehicleType:
            VehicleType.parse(m['requestedVehicleType'] as String?),
        transactionId: m['transactionId'] as String?,
        rating: m['rating'] is num ? (m['rating'] as num).toDouble() : null,
        feedback: m['feedback'] as String?,
        foodItems: (m['foodItems'] as List?)
            ?.map((e) => CartItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        restaurantId: m['restaurantId'] as String?,
        restaurantName: m['restaurantName'] as String?,
        specialRequest: m['specialRequest'] as String?,
        customerReceived: m['customerReceived'] == true,
        ratingSkipped: m['ratingSkipped'] == true,
      );

  Map<String, dynamic> toMap() => stripFirestore({
        'id': id,
        'customerId': customerId,
        'customerPhone': customerPhone,
        'driverId': driverId,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'driverPhoto': driverPhoto,
        'driverRating': driverRating,
        'operatorId': operatorId,
        'zoneId': zoneId,
        'category': category.value,
        'pickup': pickup.toMap(),
        'dropoff': dropoff.toMap(),
        'status': status.value,
        'assignedTo': assignedTo,
        'statusHistory': statusHistory?.map((e) => e.toMap()).toList(),
        'updatedAt': updatedAt,
        'price': price,
        'distance': distance,
        'commission': commission,
        'operatorCut': operatorCut,
        'driverCut': driverCut,
        'createdAt': createdAt,
        'acceptedAt': acceptedAt,
        'deliveredAt': deliveredAt,
        'cancelledAt': cancelledAt,
        'ratedAt': ratedAt,
        'notes': notes,
        'pickupNotes': pickupNotes,
        'dropoffNotes': dropoffNotes,
        'passengerCount': passengerCount,
        'prescriptionImage': prescriptionImage,
        'paymentMethod': paymentMethod.value,
        'requestedVehicleType': requestedVehicleType.value,
        'transactionId': transactionId,
        'rating': rating,
        'feedback': feedback,
        'foodItems': foodItems?.map((e) => e.toMap()).toList(),
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'specialRequest': specialRequest,
      }) as Map<String, dynamic>;
}

class Wallet {
  final double balance;
  final double totalEarnings;
  final double withdrawn;
  const Wallet(
      {this.balance = 0, this.totalEarnings = 0, this.withdrawn = 0});

  factory Wallet.fromMap(Map? m) => Wallet(
        balance: _d(m?['balance']),
        totalEarnings: _d(m?['totalEarnings']),
        withdrawn: _d(m?['withdrawn']),
      );
  Map<String, dynamic> toMap() => {
        'balance': balance,
        'totalEarnings': totalEarnings,
        'withdrawn': withdrawn,
      };
}

class UserLocation {
  final double lat;
  final double lng;
  final int updatedAt;
  const UserLocation(
      {required this.lat, required this.lng, required this.updatedAt});
  factory UserLocation.fromMap(Map m) => UserLocation(
        lat: _d(m['lat']),
        lng: _d(m['lng']),
        updatedAt: toMillis(m['updatedAt']) ?? 0,
      );
  Map<String, dynamic> toMap() =>
      {'lat': lat, 'lng': lng, 'updatedAt': updatedAt};
}

class AppUser {
  final String id;
  final String email;
  final String phone;
  final String name;
  final UserRole role;
  final UserStatus status;
  final String? photoURL;
  final VehicleType? vehicleType;
  final String? plateNumber;
  final String? operatorId;
  final String? zoneId;
  final Wallet wallet;
  final UserLocation? location;

  const AppUser({
    required this.id,
    required this.email,
    required this.phone,
    required this.name,
    required this.role,
    required this.status,
    this.photoURL,
    this.vehicleType,
    this.plateNumber,
    this.operatorId,
    this.zoneId,
    required this.wallet,
    this.location,
  });

  factory AppUser.fromMap(Map<String, dynamic> m, [String? docId]) => AppUser(
        id: _s(m['id'], docId ?? ''),
        email: _s(m['email']),
        phone: _s(m['phone']),
        name: _s(m['name']),
        role: UserRole.parse(m['role'] as String?),
        status: UserStatus.parse(m['status'] as String?),
        photoURL: m['photoURL'] as String?,
        vehicleType: VehicleType.tryParse(m['vehicleType'] as String?),
        plateNumber: m['plateNumber'] as String?,
        operatorId: m['operatorId'] as String?,
        zoneId: m['zoneId'] as String?,
        wallet: Wallet.fromMap(m['wallet'] as Map?),
        location: m['location'] is Map
            ? UserLocation.fromMap(m['location'] as Map)
            : null,
      );

  Map<String, dynamic> toMap() => stripFirestore({
        'id': id,
        'email': email,
        'phone': phone,
        'name': name,
        'role': role.value,
        'status': status.value,
        'photoURL': photoURL,
        'vehicleType': vehicleType?.value,
        'plateNumber': plateNumber,
        'operatorId': operatorId,
        'zoneId': zoneId,
        'wallet': wallet.toMap(),
        'location': location?.toMap(),
      }) as Map<String, dynamic>;
}
