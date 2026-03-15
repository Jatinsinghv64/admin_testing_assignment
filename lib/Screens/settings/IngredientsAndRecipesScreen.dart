import 'package:flutter/material.dart';
import 'IngredientsScreen.dart';
import 'RecipesScreen.dart';

/// Entry point accessed from Settings → Administration.
/// Houses a 2-tab pill bar: Ingredients | Recipes.
class IngredientsAndRecipesScreen extends StatelessWidget {
  const IngredientsAndRecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          centerTitle: true,
          title: const Text(
            'Ingredients & Recipes',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
              fontSize: 22,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(52),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(25),
              ),
              child: TabBar(
                indicator: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(25),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.deepPurple,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.blender_outlined, size: 18),
                    text: 'Ingredients',
                  ),
                  Tab(
                    icon: Icon(Icons.menu_book_outlined, size: 18),
                    text: 'Recipes',
                  ),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            IngredientsScreen(),
            RecipesScreen(),
          ],
        ),
      ),
    );
  }
}
