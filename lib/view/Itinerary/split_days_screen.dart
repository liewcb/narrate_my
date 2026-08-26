import 'package:flutter/material.dart';

class SplitDaysScreen extends StatefulWidget {
  const SplitDaysScreen({Key? key}) : super(key: key);

  @override
  State<SplitDaysScreen> createState() => _SplitDaysScreenState();
}

class _SplitDaysScreenState extends State<SplitDaysScreen> {
  // State variables to track day allocation
  final int _totalPlannedDays = 5;
  int _klDays = 3;
  int _penangDays = 2;

  // Colors based on your design
  final Color _bgColor = const Color(0xFFF6F3EB);
  final Color _primaryColor = const Color(0xFF0F3D35); // Dark green
  final Color _accentColor = const Color(0xFFFF8A65); // Peach/Orange
  final Color _textColor = const Color(0xFF1C1C1C);
  final Color _subtitleColor = const Color(0xFF9E9B93);

  void _updateDays(String city, int change) {
    setState(() {
      if (city == 'KL') {
        int newDays = _klDays + change;
        if (newDays >= 0 && (newDays + _penangDays) <= _totalPlannedDays) {
          _klDays = newDays;
        }
      } else {
        int newDays = _penangDays + change;
        if (newDays >= 0 && (_klDays + newDays) <= _totalPlannedDays) {
          _penangDays = newDays;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                _buildSummaryCard(),
                const SizedBox(height: 32),

                Text(
                  "DESTINATIONS & SCHEDULE",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: _subtitleColor,
                  ),
                ),
                const SizedBox(height: 16),

                _buildDestinationCard(
                  title: "1. Kuala Lumpur",
                  dateRange: "Day 1 – Day ${_klDays > 0 ? _klDays : 1}",
                  days: _klDays,
                  imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuCZV6HmZMWpw2n9pob1PphcQ5jAYgIF_9ciBtGwZrblZj9VWloxKBa9lHl4AwAlOocmdo1erQjnNDZQ7oINs2zo3tcZWzq4vuk_PGQtQSNBBMtHpmk1zlnMCqDUQtWtNkEmb05HfYBjKG27DNM3P7EpXmkq0d8GNZFbW4ndJsjHhOkpwHuusRudwhqX4DREOE3XAVUgb8wFJCeZHfLVZvQR2v6EF4WS9_RQbQGxt0bmORRrHzypUUzC",
                  color: _primaryColor,
                  onAdd: () => _updateDays('KL', 1),
                  onRemove: () => _updateDays('KL', -1),
                ),

                _buildTransitTip(),

                _buildDestinationCard(
                  title: "2. Penang",
                  dateRange: "Day ${_klDays + 1} – Day ${_klDays + _penangDays}",
                  days: _penangDays,
                  imageUrl: "https://lh3.googleusercontent.com/aida-public/AB6AXuCSGmdc8Ne4FOfIq5L8yhL09AQE0KOMr5lF8Obtare-7I7iomjrbyfJG5vylfv26YjQ-XCTQ0UJ3ct9825aZG11FLMne_fBOVO4NIvpcdYKCcbWDi8dJtK0mDpsTBTuVxEdGoKeiTxEaH3vN3lbOyPu6zT75cDX5bmoverzudv0GVlyecEeGGOMDf2fv6zB9SeLme54jdWi0G4O58Om3LekICJ9uCF1-yCIagZd5-p_j-NXgd87hi82",
                  color: _accentColor,
                  onAdd: () => _updateDays('Penang', 1),
                  onRemove: () => _updateDays('Penang', -1),
                ),
              ],
            ),
          ),

          // Sticky Bottom Button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildStickyFooter(),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _bgColor.withOpacity(0.9),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: _primaryColor),
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Text(
        "STEP 2 OF 3",
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: _subtitleColor,
        ),
      ),
      actions: const [
        SizedBox(width: 48), // Balances the center title
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "How would you like to split your days?",
          style: TextStyle(
            fontFamily: 'Playfair Display',
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: _textColor,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "You have $_totalPlannedDays total days planned (12–16 Aug). Allocate how many days to spend in each destination.",
          style: TextStyle(
            fontSize: 13,
            color: _subtitleColor,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    int totalAllocated = _klDays + _penangDays;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Total Duration",
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2F1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "$totalAllocated / $_totalPlannedDays Days Allocated",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (_klDays > 0)
                    Expanded(
                      flex: _klDays,
                      child: Container(color: _primaryColor),
                    ),
                  if (_klDays > 0 && _penangDays > 0)
                    const SizedBox(width: 4),
                  if (_penangDays > 0)
                    Expanded(
                      flex: _penangDays,
                      child: Container(color: _accentColor),
                    ),
                  if (totalAllocated < _totalPlannedDays) ...[
                    if (totalAllocated > 0) const SizedBox(width: 4),
                    Expanded(
                      flex: _totalPlannedDays - totalAllocated,
                      child: Container(color: Colors.grey.shade200),
                    ),
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Legend
          Row(
            children: [
              _buildLegendItem(color: _primaryColor, label: "Kuala Lumpur (${_klDays}d)"),
              const SizedBox(width: 16),
              _buildLegendItem(color: _accentColor, label: "Penang (${_penangDays}d)"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildDestinationCard({
    required String title,
    required String dateRange,
    required int days,
    required String imageUrl,
    required Color color,
    required VoidCallback onAdd,
    required VoidCallback onRemove,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Image Thumbnail
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Details & Stepper
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor),
                ),
                const SizedBox(height: 4),
                Text(
                  days > 0 ? dateRange : "No days allocated",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
                ),
                const SizedBox(height: 12),

                // Stepper Buttons
                Row(
                  children: [
                    _buildStepperBtn(icon: Icons.remove, onTap: onRemove),
                    SizedBox(
                      width: 64,
                      child: Text(
                        "$days Days",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textColor),
                      ),
                    ),
                    _buildStepperBtn(icon: Icons.add, onTap: onAdd),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepperBtn({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.grey.shade700),
      ),
    );
  }

  Widget _buildTransitTip() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.train, color: _primaryColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Travel time between KL and Penang is ~4 hours by ETS Train or 1 hr flight on 15 Aug.",
              style: TextStyle(fontSize: 11, color: _primaryColor, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStickyFooter() {
    bool isComplete = (_klDays + _penangDays) == _totalPlannedDays;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            _bgColor,
            _bgColor.withOpacity(0.9),
            _bgColor.withOpacity(0.0),
          ],
        ),
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isComplete ? _accentColor : Colors.grey.shade300,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          elevation: isComplete ? 8 : 0,
          shadowColor: _accentColor.withOpacity(0.5),
        ),
        onPressed: isComplete ? () {} : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isComplete ? "Continue to Trip Details" : "Allocate all $_totalPlannedDays days",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isComplete ? Colors.white : Colors.grey.shade600,
              ),
            ),
            if (isComplete) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}