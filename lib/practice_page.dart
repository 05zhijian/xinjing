import 'package:flutter/material.dart';
import 'practice.dart';

/// 修行闭环页：目标列表 + 今日功课打卡。
class PracticePage extends StatefulWidget {
  final PracticeData data;
  const PracticePage({super.key, required this.data});

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final TextEditingController _goalInput = TextEditingController();

  Future<void> _addGoal() async {
    final text = _goalInput.text.trim();
    if (text.isEmpty) return;
    setState(() {
      widget.data.goals.add(PracticeGoal(text));
    });
    _goalInput.clear();
    await widget.data.save();
  }

  Future<void> _toggleGoal(PracticeGoal g) async {
    setState(() => g.done = !g.done);
    await widget.data.save();
  }

  Future<void> _deleteGoal(PracticeGoal g) async {
    setState(() => widget.data.goals.remove(g));
    await widget.data.save();
  }

  Future<void> _setTodayCheckin(bool done) async {
    setState(() {
      if (done) {
        widget.data.checkins[PracticeData.today()] = true;
      } else {
        widget.data.checkins.remove(PracticeData.today());
      }
    });
    await widget.data.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _checkinCard(),
          const SizedBox(height: 16),
          Text('我的目标',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _goalInput,
                  decoration: InputDecoration(
                    hintText: '添加一个目标…',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _addGoal(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '添加目标',
                icon: const Icon(Icons.add),
                onPressed: _addGoal,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.data.goals.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('还没有目标，写下第一个吧',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...widget.data.goals.map(_goalTile),
        ],
      ),
    );
  }

  Widget _checkinCard() {
    final done = widget.data.todayDone;
    return Card(
      elevation: 0,
      color: done ? const Color(0xFFE3F0E6) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: done ? const Color(0xFF5C8A6E) : Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? const Color(0xFF5C8A6E) : Colors.grey.shade400,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(done ? '今日功课已完成' : '今日功课',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    done ? '你已经为显化向前迈了一步' : '今天做一件小功课，觉察、书写或静坐都可以',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => _setTodayCheckin(!done),
              child: Text(done ? '撤销' : '完成'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _goalTile(PracticeGoal g) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Checkbox(
          value: g.done,
          onChanged: (_) => _toggleGoal(g),
        ),
        title: Text(
          g.text,
          style: TextStyle(
            decoration: g.done ? TextDecoration.lineThrough : null,
            color: g.done ? Colors.grey : null,
          ),
        ),
        trailing: IconButton(
          tooltip: '删除',
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => _deleteGoal(g),
        ),
      ),
    );
  }
}
