import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'reports_service.dart';
import '../management/admin_management_service.dart';
import '../inventory/inventory_service.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.shopId, this.initialDate});
  final String shopId;
  final DateTime? initialDate;
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _service = ReportsService();
  final _search = TextEditingController();
  String _type = 'All';
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final records = _service.reports(widget.shopId, type: _type, search: _search.text, date: _date);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reports', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Color(0xFF1D2941))),
              const SizedBox(height: 8),
              const Text('Complete transaction history', style: TextStyle(color: Color(0xFF6A7283))),
              const SizedBox(height: 22),
              if (compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search customer, report ID, bill number, product, or IMEI',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_date == null ? 'Date' : '${_date!.day}/${_date!.month}/${_date!.year}'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17)),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search customer, report ID, bill number, product, or IMEI',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(_date == null ? 'Date' : '${_date!.day}/${_date!.month}/${_date!.year}'),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17)),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: ['All', 'Mobile Sale', 'Accessories Sale', 'Repair', 'Debt']
                    .map((type) => ChoiceChip(
                          label: Text(type),
                          selected: _type == type,
                          onSelected: (_) => setState(() => _type = type),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E7EF)),
                  ),
                  child: records.isEmpty
                      ? const Center(
                          child: Text('No transactions found', style: TextStyle(color: Color(0xFF6A7283))),
                        )
                      : ListView.separated(
                          itemCount: records.length,
                          separatorBuilder: (_, index) => const Divider(height: 1),
                          itemBuilder: (_, index) => _reportTile(records[index]),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _reportTile(ReportRecord record) => ListTile(onTap: () => _showDetails(record), contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), leading: CircleAvatar(backgroundColor: const Color(0xFFE7E3FF), child: Icon(_icon(record.type), color: const Color(0xFF4E2BCB))), title: Row(children: [Expanded(child: Text(record.type, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1D2941)))), Text(record.id, style: const TextStyle(fontSize: 12, color: Color(0xFF6A7283)))]), subtitle: Text('${record.person}  •  ${record.description}\n${record.dateTime.toLocal()}'), trailing: Text('PKR ${record.amount.abs().toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.w700, color: record.amount < 0 ? Colors.orange.shade800 : const Color(0xFF1D2941))));

  Future<void> _pickDate() async { final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: _date ?? DateTime.now()); if (picked != null && mounted) setState(() => _date = picked); }

  void _showDetails(ReportRecord record) { final details = _service.shopDetails(widget.shopId); showDialog<void>(context: context, builder: (context) => AlertDialog(title: Text(record.type), content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500), child: SingleChildScrollView(child: _ThermalReceipt(record: record, details: details))), actions: [
    if (record.billNumber != null && record.billNumber!.isNotEmpty && record.type.contains('Sale'))
      TextButton.icon(
        onPressed: () async {
          final result = InventoryService().returnSaleByBillNumber(
            shopId: widget.shopId,
            billNumber: record.billNumber!,
            returnReason: 'Returned from report',
          );
          if (!mounted) return;
          if (result != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
            return;
          }
          Navigator.pop(context);
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale returned successfully.')));
        },
        icon: const Icon(Icons.undo),
        label: const Text('Return Sale'),
      ),
    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
    ElevatedButton.icon(onPressed: () => _print(record), icon: const Icon(Icons.print), label: const Text('Print Bill')),
  ])); }

  Future<void> _print(ReportRecord record) async { final details = _service.shopDetails(widget.shopId); final document = _receipt(details.name, details.address, details.phone, record); await Printing.layoutPdf(onLayout: (_) => document.save()); }

  pw.Document _receipt(String name, String address, String phone, ReportRecord record) {
    final document = pw.Document();
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, 220 * PdfPageFormat.mm, marginAll: 3 * PdfPageFormat.mm),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(child: pw.Text(name.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            pw.Center(child: pw.Text(address)),
            pw.Center(child: pw.Text('Phone: $phone')),
            pw.Divider(),
            pw.Center(child: pw.Text(record.type.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
            if (record.billNumber != null && record.billNumber!.isNotEmpty) pw.Text('Bill Number: ${record.billNumber}'),
            pw.Text('Report ID: ${record.id}'),
            pw.Text('Type: ${record.type}'),
            pw.Text('Date: ${record.dateTime.toLocal()}'),
            pw.Text('Customer: ${record.person}'),
            pw.Divider(),
            ...record.detail.split('\n').map(pw.Text.new),
            pw.Divider(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Total'),
              pw.Text('PKR ${record.amount.abs().toStringAsFixed(0)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ]),
            pw.SizedBox(height: 18),
            pw.Center(child: pw.Text('Thank you for your purchase!')),
            pw.Center(child: pw.Text('Developed By Arslan Kharal')),
          ],
        ),
      ),
    );
    return document;
  }

  IconData _icon(String type) => type == 'Repair' ? Icons.build_outlined : type == 'Debt' ? Icons.account_balance_wallet_outlined : type == 'Mobile Sale' ? Icons.phone_iphone : Icons.inventory_2_outlined;
}

class _ThermalReceipt extends StatelessWidget {
  const _ThermalReceipt({required this.record, required this.details});
  final ReportRecord record;
  final ShopDetails details;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 390),
    child: Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFFFFFEFA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text(details.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
          Center(child: Text(details.address)),
          Center(child: Text('Phone: ${details.phone}')),
          Center(child: Text(record.type.toUpperCase())),
          const Divider(),
          if (record.billNumber != null && record.billNumber!.isNotEmpty) Text('Bill Number: ${record.billNumber}'),
          Text('Report ID: ${record.id}'),
          Text('Type: ${record.type}'),
          Text('Date: ${record.dateTime.toLocal()}'),
          Text('Customer: ${record.person}'),
          const Divider(),
          ...record.detail.split('\n').map(Text.new),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)), Text('PKR ${record.amount.abs().toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700))]),
          const SizedBox(height: 18),
          const Center(child: Text('Thank you for your purchase!')),
          const Center(child: Text('Developed By Arslan Kharal')),
        ],
      ),
    ),
  );
}
