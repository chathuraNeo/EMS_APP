import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../core/app_theme.dart';

class MoreHubScreen extends StatelessWidget {
  const MoreHubScreen({
    super.key,
    required this.currentRole,
    required this.onOpenSection,
    this.onOpenNotifications,
  });

  final UserRole currentRole;
  final ValueChanged<String> onOpenSection;
  final VoidCallback? onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.cream,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          _buildSliverAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildQuickActionChips(context),
                const SizedBox(height: 18),
                if (currentRole == UserRole.cashOwner || currentRole == UserRole.unknown) ...[
                  _buildSectionTitle('Primary Management', 'Core executive controls'),
                  const SizedBox(height: 10),
                  _buildPrimaryHeroGrid(context),
                  const SizedBox(height: 22),
                  _buildSectionTitle('Banking & Cash Assets', 'Safes, bank liquidity & transfers'),
                  const SizedBox(height: 10),
                  _buildBankingGrid(context),
                  const SizedBox(height: 22),
                  _buildSectionTitle('Audits & Governance', 'Field balances & reconciliations'),
                  const SizedBox(height: 10),
                  _buildAuditsGrid(context),
                  const SizedBox(height: 22),
                  _buildSectionTitle('Analytics & Logistics', 'Statements, categories & fleet'),
                  const SizedBox(height: 10),
                  _buildAnalyticsGrid(context),
                ] else if (currentRole == UserRole.manager) ...[
                  _buildSectionTitle('Manager Suite', 'Field supervision & operations'),
                  const SizedBox(height: 10),
                  _buildManagerHeroGrid(context),
                  const SizedBox(height: 22),
                  _buildSectionTitle('Team & Fleet Operations', 'Audit field members & vehicle trips'),
                  const SizedBox(height: 10),
                  _buildManagerOperationsGrid(context),
                ] else ...[
                  _buildSectionTitle('Member Float Portal', 'Personal float, expenses & fleet'),
                  const SizedBox(height: 10),
                  _buildMemberGrid(context),
                ],
                const SizedBox(height: 22),
                _buildSectionTitle('Preferences & System', 'Application settings & profile'),
                const SizedBox(height: 10),
                _buildSettingsSection(context),
                const SizedBox(height: 36),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context) {
    final roleName = currentRole.displayName;
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: AppTheme.card,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 16,
      expandedHeight: 90,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x262563EB),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Operations Hub',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    '$roleName Executive Suite',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    roleName.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1D4ED8),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionChips(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildQuickChip(
            icon: Icons.fact_check_rounded,
            label: 'Cheques',
            color: const Color(0xFF2563EB),
            onTap: () => onOpenSection('cash_owner_cheques'),
          ),
          const SizedBox(width: 8),
          _buildQuickChip(
            icon: Icons.manage_accounts_rounded,
            label: 'User Admin',
            color: const Color(0xFF059669),
            onTap: () => onOpenSection('cash_owner_users'),
          ),
          const SizedBox(width: 8),
          _buildQuickChip(
            icon: Icons.swap_horiz_rounded,
            label: 'Transfer',
            color: const Color(0xFF7C3AED),
            onTap: () => onOpenSection('cash_owner_wallet_transfer'),
          ),
          const SizedBox(width: 8),
          _buildQuickChip(
            icon: Icons.account_balance_rounded,
            label: 'Banks',
            color: const Color(0xFF0284C7),
            onTap: () => onOpenSection('cash_owner_banks'),
          ),
          const SizedBox(width: 8),
          _buildQuickChip(
            icon: Icons.analytics_rounded,
            label: 'Reports',
            color: const Color(0xFFE11D48),
            onTap: () => onOpenSection('cash_owner_reports'),
          ),
          const SizedBox(width: 8),
          _buildQuickChip(
            icon: Icons.directions_car_rounded,
            label: 'Trips',
            color: const Color(0xFFD97706),
            onTap: () => onOpenSection('cash_owner_vehicles'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  // Large Featured Hero Cards (Cheques & User Management)
  Widget _buildPrimaryHeroGrid(BuildContext context) {
    return Column(
      children: [
        _buildHeroCard(
          title: 'Cheque Management',
          badge: 'Cash In / Out',
          subtitle: 'Bank cheques, clearances, pending collections & issued vouchers',
          icon: Icons.fact_check_rounded,
          gradient: const [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          onTap: () => onOpenSection('cash_owner_cheques'),
        ),
        const SizedBox(height: 12),
        _buildHeroCard(
          title: 'Manage All Users',
          badge: 'Team Admin',
          subtitle: 'Supervise managers, assign members, control login access & roles',
          icon: Icons.manage_accounts_rounded,
          gradient: const [Color(0xFF065F46), Color(0xFF059669)],
          onTap: () => onOpenSection('cash_owner_users'),
        ),
      ],
    );
  }

  Widget _buildHeroCard({
    required String title,
    required String badge,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.last.withOpacity(0.3),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'Open Console',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Banking Grid
  Widget _buildBankingGrid(BuildContext context) {
    return _buildCardGrid([
      _HubItem(
        title: 'Bank Accounts',
        subtitle: 'Live liquidity & balances',
        icon: Icons.account_balance_rounded,
        color: const Color(0xFF0284C7),
        action: 'cash_owner_banks',
      ),
      _HubItem(
        title: 'Cash Safes',
        subtitle: 'Physical vaults & drawers',
        icon: Icons.payments_rounded,
        color: const Color(0xFFD97706),
        action: 'cash_owner_cash_safes',
      ),
      _HubItem(
        title: 'Wallet Transfer',
        subtitle: 'Inter-wallet fund shift',
        icon: Icons.swap_horiz_rounded,
        color: const Color(0xFF7C3AED),
        action: 'cash_owner_wallet_transfer',
      ),
      _HubItem(
        title: 'Top-up History',
        subtitle: 'Bank deposit slip credits',
        icon: Icons.archive_rounded,
        color: const Color(0xFF059669),
        action: 'cash_owner_topup_history',
      ),
    ]);
  }

  // Audits Grid
  Widget _buildAuditsGrid(BuildContext context) {
    return _buildCardGrid([
      _HubItem(
        title: 'Team Audit',
        subtitle: 'Member & manager balances',
        icon: Icons.person_search_rounded,
        color: const Color(0xFF0D9488),
        action: 'cash_owner_user_audit',
      ),
      _HubItem(
        title: 'Wallet Audit',
        subtitle: 'Vault ledger & daily logs',
        icon: Icons.history_edu_rounded,
        color: const Color(0xFF475569),
        action: 'cash_owner_wallet_audit',
      ),
    ]);
  }

  // Analytics Grid
  Widget _buildAnalyticsGrid(BuildContext context) {
    return _buildCardGrid([
      _HubItem(
        title: 'Financial Reports',
        subtitle: 'Monthly summaries & audits',
        icon: Icons.analytics_rounded,
        color: const Color(0xFFE11D48),
        action: 'cash_owner_reports',
      ),
      _HubItem(
        title: 'Vehicle Fleet',
        subtitle: 'Trips, mileage & fuel logs',
        icon: Icons.directions_car_filled_rounded,
        color: const Color(0xFFEA580C),
        action: 'cash_owner_vehicles',
      ),
      _HubItem(
        title: 'Expense Categories',
        subtitle: 'Cost allocation tags',
        icon: Icons.category_rounded,
        color: const Color(0xFF4F46E5),
        action: 'cash_owner_categories',
      ),
      _HubItem(
        title: 'Executive Summary',
        subtitle: 'Live KPI cards & trends',
        icon: Icons.dashboard_rounded,
        color: const Color(0xFF2563EB),
        action: 'cash_owner_home',
      ),
    ]);
  }

  // Manager Grids
  Widget _buildManagerHeroGrid(BuildContext context) {
    return Column(
      children: [
        _buildHeroCard(
          title: 'Field Team Members',
          badge: 'Operations',
          subtitle: 'Audit assigned members, track personal floats & claims submitted',
          icon: Icons.people_alt_rounded,
          gradient: const [Color(0xFF0F766E), Color(0xFF0D9488)],
          onTap: () => onOpenSection('manager_members'),
        ),
        const SizedBox(height: 12),
        _buildHeroCard(
          title: 'Vehicle & Trip Fleet',
          badge: 'Fleet',
          subtitle: 'Dispatch vehicles, review trip logs, audit fuel consumption',
          icon: Icons.directions_car_filled_rounded,
          gradient: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
          onTap: () => onOpenSection('manager_vehicles'),
        ),
      ],
    );
  }

  Widget _buildManagerOperationsGrid(BuildContext context) {
    return _buildCardGrid([
      _HubItem(
        title: 'Claims Audit',
        subtitle: 'Inspect submitted receipts',
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFFE11D48),
        action: 'manager_claims',
      ),
      _HubItem(
        title: 'Disbursements',
        subtitle: 'Float payouts & transfers',
        icon: Icons.payments_rounded,
        color: const Color(0xFF059669),
        action: 'manager_payment',
      ),
      _HubItem(
        title: 'Operations Dashboard',
        subtitle: 'Summary & team activity',
        icon: Icons.dashboard_rounded,
        color: const Color(0xFF2563EB),
        action: 'manager_home',
      ),
      _HubItem(
        title: 'Manager Settings',
        subtitle: 'Portal profile & security',
        icon: Icons.tune_rounded,
        color: const Color(0xFF475569),
        action: 'manager_settings',
      ),
    ]);
  }

  // Member Grid
  Widget _buildMemberGrid(BuildContext context) {
    return _buildCardGrid([
      _HubItem(
        title: 'My Claim Submissions',
        subtitle: 'Upload receipts & track approvals',
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF059669),
        action: 'member_claims',
      ),
      _HubItem(
        title: 'Assigned Float Funds',
        subtitle: 'Personal float statement',
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF2563EB),
        action: 'member_funds',
      ),
      _HubItem(
        title: 'Return Payment',
        subtitle: 'Settle remaining float balance',
        icon: Icons.assignment_return_rounded,
        color: const Color(0xFFD97706),
        action: 'member_return',
      ),
      _HubItem(
        title: 'Vehicle Trips',
        subtitle: 'Log vehicle odometer & fuel',
        icon: Icons.directions_car_filled_rounded,
        color: const Color(0xFF7C3AED),
        action: 'member_vehicles',
      ),
    ]);
  }

  Widget _buildSettingsSection(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSettingsTile(
            icon: Icons.tune_rounded,
            color: const Color(0xFF2563EB),
            title: 'Site Settings & Customization',
            subtitle: 'Company logo, theme color & currency symbol',
            onTap: () => onOpenSection('cash_owner_settings'),
          ),
          const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),
          _buildSettingsTile(
            icon: Icons.notifications_none_rounded,
            color: const Color(0xFF059669),
            title: 'Push Notifications',
            subtitle: 'System alerts, payouts & claims activity',
            onTap: onOpenNotifications ?? () {},
          ),
          const Divider(height: 1, indent: 56, endIndent: 16, color: Color(0xFFF1F5F9)),
          _buildSettingsTile(
            icon: Icons.refresh_rounded,
            color: const Color(0xFF7C3AED),
            title: 'Refresh Session',
            subtitle: 'Reload latest financial records and balances',
            onTap: () => onOpenSection('cash_owner_home'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0F172A),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF64748B),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: Color(0xFF94A3B8),
      ),
    );
  }

  Widget _buildCardGrid(List<_HubItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.45,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return InkWell(
          onTap: () => onOpenSection(item.action),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF1F5F9)),
              boxShadow: [
                BoxShadow(
                  color: item.color.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: item.color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: item.color, size: 20),
                    ),
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 14,
                      color: item.color.withOpacity(0.6),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HubItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String action;

  const _HubItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.action,
  });
}
