/// The livestock taxonomy the whole app shares: the six categories a seller
/// can post under, and the types inside each one.
///
/// Lived in `seller.dart` as a private field until Explore needed to browse
/// by it too. Sellers pick from these lists when publishing, so the strings
/// here are exactly what lands in `listings.category` / `listings.subcategory`
/// — changing one means migrating existing rows.
library;

import 'package:flutter/material.dart';

/// Categories in the order they're shown, without the 'All' pseudo-entry.
const List<String> kLivestockCategories = [
  'Poultry',
  'Small Livestock',
  'Large Livestock',
  'Aquaculture',
  'Ornamental Fish',
  'Hatching & Breeding Products',
];

/// Types offered once a category is picked.
const Map<String, List<String>> kLivestockSubcategories = {
  'Poultry': [
    'Chicken',
    'Gamefowl',
    'Duck',
    'Turkey',
    'Peacock',
    'Pigeon',
    'Quail',
    'Guinea Fowl',
    'Ostrich',
    'Dove',
    'Goose',
  ],
  'Large Livestock': [
    'Pig',
    'Goat',
    'Cattle',
    'Water Buffalo',
    'Sheep',
    'Horse',
  ],
  'Small Livestock': ['Rabbit', 'Guinea Pig', 'Hamster', 'Hedgehog'],
  'Aquaculture': [
    'Tilapia',
    'Milkfish (Bangus)',
    'Catfish (Hito)',
    'Carp',
    'Gourami',
    'Eel',
    'Mudfish',
    'Mud Crab (Alimango)',
    'Oyster',
    'Mussel',
    'Clam',
    'Sea Cucumber',
    'Seaweed Seedlings',
    'Lobster',
    'Prawn',
    'Shrimp',
  ],
  'Ornamental Fish': [
    'Koi',
    'Goldfish',
    'Betta',
    'Guppy',
    'Molly',
    'Platy',
    'Swordtail',
    'Flowerhorn',
    'Arowana',
    'Discus',
    'Angelfish',
    'Oscar',
    'Cichlids',
    'Tetra',
    'Stingray',
    'Pleco',
    'Dragon Fish',
    'Aquarium Shrimp',
    'Aquarium snails',
  ],
  'Hatching & Breeding Products': [
    'Fertile chicken eggs',
    'Fertile duck eggs',
    'Fertile turkey eggs',
    'Fertile quail eggs',
    'Fertile goose eggs',
    'Chicks',
    'Ducklings',
    'Turkey poults',
    'Quail chicks',
  ],
};

/// Icon that stands in for a category — used on the picker rows and as the
/// last-resort artwork on a browse tile.
IconData livestockCategoryIcon(String category) {
  switch (category) {
    case 'All':
      return Icons.grid_view;
    case 'Poultry':
      return Icons.egg_alt;
    case 'Aquaculture':
      return Icons.set_meal;
    case 'Ornamental Fish':
      return Icons.water_drop_outlined;
    case 'Hatching & Breeding Products':
      return Icons.egg_outlined;
    default:
      return Icons.pets;
  }
}

/// Bundled artwork for a category or type, when one ships with the app.
///
/// Only a handful exist so far; everything else falls back to a real photo
/// from a listing in that bucket (see Explore's browse tiles). Add a file to
/// `images/` and a line here to give another one fixed artwork.
String? livestockAsset(String name) {
  const assets = <String, String>{
    'Poultry': 'images/whitehen.png',
    'Chicken': 'images/chicken.png',
    'Duck': 'images/duck.png',
    'Turkey': 'images/turkey.png',
  };
  return assets[name];
}
