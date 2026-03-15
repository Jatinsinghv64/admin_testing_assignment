import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';
import 'CouponsScreen.dart';
import 'ComboMealsScreen.dart';
import 'PromoSalesScreen.dart';

class PromoSettingsScreen extends StatelessWidget {
  const PromoSettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.deepPurple),
        title: const Text(
          'Promotions & Deals',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
            fontSize: 24,
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildPromoOptionCard(
                context,
                icon: Icons.fastfood_rounded,
                iconColor: Colors.orange,
                title: 'Combo Meals',
                subtitle: 'Group items together for a discounted price.',
                destination: const ComboMealsScreen(),
              ),
              const SizedBox(height: 16),
              _buildPromoOptionCard(
                context,
                icon: Icons.campaign_rounded,
                iconColor: Colors.pink,
                title: 'Promo Sales',
                subtitle:
                    'Run percentage or fixed amount discounts on items or categories.',
                destination: const PromoSalesScreen(),
              ),
              const SizedBox(height: 16),
              _buildPromoOptionCard(
                context,
                icon: Icons.card_giftcard_rounded,
                iconColor: Colors.teal,
                title: 'Coupon Codes',
                subtitle:
                    'Create manual discount codes for customers to apply at checkout.',
                destination: const CouponManagementScreen(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromoOptionCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget destination,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => destination),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 30),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
