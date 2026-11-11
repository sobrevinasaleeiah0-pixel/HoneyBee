import 'package:firebase_database/firebase_database.dart';

class DataInitializer {
  static DatabaseReference get _db => FirebaseDatabase.instance.ref();

  static Future<void> seedInitialData() async {
    final productsSnap = await _db.child('products').get();
    final existingProducts = productsSnap.value;
    final shouldSeedProducts =
        !productsSnap.exists ||
        existingProducts == null ||
        (existingProducts is Map && existingProducts.isEmpty);
    late final Map<String, dynamic> inventoryProducts;

    if (shouldSeedProducts) {
      print('Seeding initial product data...');

      final Map<String, dynamic> initialProducts = {
        'prod_mellifera': {
          'id': 'prod_mellifera',
          'name': 'Sweet Honey (Mellifera)',
          'variety': 'Mellifera',
          'category': 'Sweet Honey',
          'isActive': true,
          'createdDate': ServerValue.timestamp,
          'variants': {
            'v_mel_200g': {
              'id': 'v_mel_200g',
              'size': '200g',
              'price': 210,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_mel_250g': {
              'id': 'v_mel_250g',
              'size': '250g',
              'price': 260,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_mel_350g': {
              'id': 'v_mel_350g',
              'size': '350g',
              'price': 360,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_mel_400g': {
              'id': 'v_mel_400g',
              'size': '400g',
              'price': 410,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_mel_500g': {
              'id': 'v_mel_500g',
              'size': '500g',
              'price': 510,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_mel_660g': {
              'id': 'v_mel_660g',
              'size': '660g',
              'price': 660,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_mel_1kg': {
              'id': 'v_mel_1kg',
              'size': '1kg',
              'price': 1010,
              'reorderLevel': 5,
              'isActive': true,
            },
          },
        },
        'prod_pukyutan': {
          'id': 'prod_pukyutan',
          'name': 'Pukyutan Honey',
          'variety': 'Pukyutan',
          'category': 'Pukyutan Honey',
          'isActive': true,
          'createdDate': ServerValue.timestamp,
          'variants': {
            'v_puk_200g': {
              'id': 'v_puk_200g',
              'size': '200g',
              'price': 230,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_puk_250g': {
              'id': 'v_puk_250g',
              'size': '250g',
              'price': 285,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_puk_350g': {
              'id': 'v_puk_350g',
              'size': '350g',
              'price': 395,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_puk_400g': {
              'id': 'v_puk_400g',
              'size': '400g',
              'price': 450,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_puk_500g': {
              'id': 'v_puk_500g',
              'size': '500g',
              'price': 560,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_puk_650g': {
              'id': 'v_puk_650g',
              'size': '650g',
              'price': 725,
              'reorderLevel': 10,
              'isActive': true,
            },
            'v_puk_1kg': {
              'id': 'v_puk_1kg',
              'size': '1kg',
              'price': 1110,
              'reorderLevel': 5,
              'isActive': true,
            },
          },
        },
        'prod_lukot': {
          'id': 'prod_lukot',
          'name': 'Stingless Bees (Lukot)',
          'variety': 'Lukot',
          'category': 'Stingless Bees',
          'isActive': true,
          'createdDate': ServerValue.timestamp,
          'variants': {
            'v_luk_350g': {
              'id': 'v_luk_350g',
              'size': '350g',
              'price': 420,
              'reorderLevel': 5,
              'isActive': true,
            },
            'v_luk_400g': {
              'id': 'v_luk_400g',
              'size': '400g',
              'price': 480,
              'reorderLevel': 5,
              'isActive': true,
            },
            'v_luk_500g': {
              'id': 'v_luk_500g',
              'size': '500g',
              'price': 600,
              'reorderLevel': 5,
              'isActive': true,
            },
            'v_luk_650g': {
              'id': 'v_luk_650g',
              'size': '650g',
              'price': 780,
              'reorderLevel': 5,
              'isActive': true,
            },
            'v_luk_1kg': {
              'id': 'v_luk_1kg',
              'size': '1kg',
              'price': 1200,
              'reorderLevel': 3,
              'isActive': true,
            },
          },
        },
        'prod_others': {
          'id': 'prod_others',
          'name': 'Other Honey Products',
          'variety': 'Others',
          'category': 'Others',
          'isActive': true,
          'createdDate': ServerValue.timestamp,
          'variants': {
            'v_pollen_500g': {
              'id': 'v_pollen_500g',
              'size': 'Honey With Pollen 500g',
              'price': 800,
              'reorderLevel': 5,
              'isActive': true,
            },
            'v_wax_1kg': {
              'id': 'v_wax_1kg',
              'size': 'Bees Wax (kg)',
              'price': 650,
              'reorderLevel': 5,
              'isActive': true,
            },
            'v_propolis_100g': {
              'id': 'v_propolis_100g',
              'size': 'Propolis (100g)',
              'price': 500,
              'reorderLevel': 5,
              'isActive': true,
            },
            'v_comb_650g': {
              'id': 'v_comb_650g',
              'size': 'Honeycomb (650g)',
              'price': 845,
              'reorderLevel': 5,
              'isActive': true,
            },
          },
        },
      };

      await _db.child('products').set(initialProducts);
      inventoryProducts = initialProducts;
      print('Initial product data seeded successfully.');
    } else {
      inventoryProducts = existingProducts is Map
          ? Map<String, dynamic>.from(existingProducts)
          : <String, dynamic>{};
    }

    await _ensureMissingInventory(inventoryProducts);
  }

  static Future<void> _ensureMissingInventory(
    Map<String, dynamic> products,
  ) async {
    final inventoryRef = _db.child('inventory');
    await inventoryRef
        .runTransaction((Object? currentValue) {
          final inventory = currentValue is Map
              ? Map<dynamic, dynamic>.from(currentValue)
              : <dynamic, dynamic>{};
          var changed = false;

          products.forEach((productId, productValue) {
            if (productValue is! Map || productValue['variants'] is! Map) {
              return;
            }

            final variants = productValue['variants'] as Map;
            final existingProduct = inventory[productId];
            if (existingProduct == null) {
              final productInventory = <dynamic, dynamic>{};
              variants.forEach((variantId, _) {
                productInventory[variantId] = {
                  'quantity': 0,
                  'lastUpdated': ServerValue.timestamp,
                };
              });
              if (productInventory.isNotEmpty) {
                inventory[productId] = productInventory;
                changed = true;
              }
              return;
            }

            if (existingProduct is! Map) {
              return;
            }
            final productInventory = Map<dynamic, dynamic>.from(
              existingProduct,
            );
            var productChanged = false;
            variants.forEach((variantId, _) {
              if (productInventory.containsKey(variantId)) {
                return;
              }
              productInventory[variantId] = {
                'quantity': 0,
                'lastUpdated': ServerValue.timestamp,
              };
              changed = true;
              productChanged = true;
            });
            if (productChanged) inventory[productId] = productInventory;
          });

          return changed ? Transaction.success(inventory) : Transaction.abort();
        })
        .timeout(const Duration(seconds: 12));
  }
}
