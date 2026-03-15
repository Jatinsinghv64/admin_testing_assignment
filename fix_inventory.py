import re

file_path = "lib/Screens/inventory/InventoryDashboardScreen.dart"
with open(file_path, "r") as f:
    content = f.read()

# Replace categoryName logic in InventoryDashboardScreen
# We want to wrap the StreamBuilder for menu_items with a StreamBuilder for menu_categories.

original_builder_start = """    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {"""

new_builder_start = """    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('menu_categories').snapshots(),
      builder: (context, catSnap) {
        final catMap = <String, String>{};
        if (catSnap.hasData) {
          for (var doc in catSnap.data!.docs) {
            catMap[doc.id] = (doc.data() as Map<String, dynamic>)['name'] ?? 'Unnamed';
          }
        }
        return StreamBuilder<QuerySnapshot>(
          stream: query.snapshots(),
          builder: (context, snapshot) {"""

content = content.replace(original_builder_start, new_builder_start)

# We also need to close the extra StreamBuilder at the end of _MenuItemsManagementTabState build method
# Let's find the end of the method.
# It ends with:
#           ),
#         );
#       },
#     );
#   }
# }
end_pattern = """        );
      },
    );
  }
}"""
new_end_pattern = """        );
      },
    );
      },
    );
  }
}"""

content = content.replace(end_pattern, new_end_pattern)

# Replace categoryName
content = content.replace(
    "final categoryName = data['categoryName'] as String? ?? '';",
    "final categoryName = catMap[data['categoryId']] ?? 'Uncategorized';"
)

with open(file_path, "w") as f:
    f.write(content)

print("Fixed InventoryDashboardScreen")
