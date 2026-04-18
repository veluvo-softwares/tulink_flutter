import 'package:flutter/material.dart';
import '../../../../core/theme/tulink_colors.dart';

class InviteParticipantsScreen extends StatefulWidget {
  final String journeyId;
  static const String routeName = '/invite-participants';

  const InviteParticipantsScreen({
    super.key,
    required this.journeyId,
  });

  @override
  State<InviteParticipantsScreen> createState() => _InviteParticipantsScreenState();
}

class _InviteParticipantsScreenState extends State<InviteParticipantsScreen> {
  final TextEditingController _emailController = TextEditingController();
  final List<String> _invitedEmails = [];

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _addEmail() {
    final email = _emailController.text.trim();
    if (email.isNotEmpty && email.contains('@') && !_invitedEmails.contains(email)) {
      setState(() {
        _invitedEmails.add(email);
        _emailController.clear();
      });
    }
  }

  void _removeEmail(String email) {
    setState(() {
      _invitedEmails.remove(email);
    });
  }

  void _sendInvitations() {
    if (_invitedEmails.isEmpty) return;

    // TODO: Implement invitation sending logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Invitations sent to ${_invitedEmails.length} participants'),
        backgroundColor: Colors.green,
      ),
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).tulinkColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite Participants'),
        backgroundColor: colors.cardDark,
        foregroundColor: colors.white,
      ),
      backgroundColor: colors.carbonBlack,
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add participants to your journey',
              style: TextStyle(
                color: colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Email input field
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.brushedSteel.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _emailController,
                      style: TextStyle(color: colors.white),
                      decoration: InputDecoration(
                        hintText: 'Enter email address',
                        hintStyle: TextStyle(color: colors.silver),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (_) => _addEmail(),
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  GestureDetector(
                    onTap: _addEmail,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.electricRed,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.add,
                        color: colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Invited emails list
            if (_invitedEmails.isNotEmpty) ...[
              Text(
                'Invited Participants (${_invitedEmails.length})',
                style: TextStyle(
                  color: colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 12),
              
              Expanded(
                child: ListView.builder(
                  itemCount: _invitedEmails.length,
                  itemBuilder: (context, index) {
                    final email = _invitedEmails[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.cardDark,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colors.brushedSteel.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            color: colors.silver,
                            size: 20,
                          ),
                          
                          const SizedBox(width: 12),
                          
                          Expanded(
                            child: Text(
                              email,
                              style: TextStyle(
                                color: colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          
                          GestureDetector(
                            onTap: () => _removeEmail(email),
                            child: Icon(
                              Icons.close,
                              color: colors.electricRed,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ] else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.people_outline,
                        color: colors.silver,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No participants invited yet',
                        style: TextStyle(
                          color: colors.silver,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add email addresses to invite participants',
                        style: TextStyle(
                          color: colors.silver.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Send invitations button
            if (_invitedEmails.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 20),
                child: ElevatedButton(
                  onPressed: _sendInvitations,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.electricRed,
                    foregroundColor: colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Send ${_invitedEmails.length} Invitation${_invitedEmails.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}