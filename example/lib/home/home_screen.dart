import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vital_core/services/data/user.dart';
import 'package:vital_flutter_example/home/home_bloc.dart';
import 'package:vital_flutter_example/routes.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeBloc bloc = context.watch<HomeBloc>();

    return Scaffold(
        appBar: AppBar(
          title: const Text('Vital SDK example app'),
          actions: [
            IconButton(
              onPressed: () => Navigator.of(context).pushNamed(Routes.devices),
              icon: const Icon(Icons.bluetooth),
            ),
            IconButton(
              onPressed: () => _displayCreateUserDialog(context),
              icon: const Icon(Icons.person_add),
            ),
            IconButton(
              onPressed: () => bloc.refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: const UsersPage());
  }
}

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final HomeBloc bloc = Provider.of(context);
    return StreamBuilder(
      stream: bloc.getUsers(),
      builder: (context, AsyncSnapshot<List<User>?> snapshot) {
        final users = snapshot.data;
        if (users == null) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        return SafeArea(
          child: Column(children: [
            Expanded(
                child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemBuilder: ((context, index) => UserWidget(
                    user: users[index],
                    isCurrentSDKUser: users[index].userId == bloc.currentUserId,
                    linkAction: () => bloc.launchLink(users[index]),
                    deleteAction: () => bloc.deleteUser(users[index]),
                    onTap: () {
                      Navigator.of(context)
                          .pushNamed(Routes.user, arguments: users[index]);
                    },
                  )),
              itemCount: users.length,
            )),
          ]),
        );
      },
    );
  }
}

class UserWidget extends StatelessWidget {
  final User user;
  final VoidCallback? linkAction;
  final VoidCallback? deleteAction;
  final VoidCallback? onTap;
  final bool isCurrentSDKUser;

  const UserWidget({
    super.key,
    required this.user,
    required this.isCurrentSDKUser,
    this.linkAction,
    this.deleteAction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        child: Column(children: [
          Row(
            children: [
              const Icon(Icons.person, color: Colors.grey, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  user.clientUserId ?? '',
                  style: const TextStyle(fontSize: 18.0),
                ),
              ),
              if (linkAction != null && isCurrentSDKUser) ...[
                const SizedBox(width: 12),
                IconButton(
                  onPressed: linkAction,
                  icon: const Icon(
                    Icons.copy,
                    color: Colors.grey,
                  ),
                )
              ],
              if (deleteAction != null) ...[
                const SizedBox(width: 12),
                IconButton(
                  onPressed: deleteAction,
                  icon: const Icon(
                    Icons.delete,
                    color: Colors.grey,
                  ),
                ),
              ]
            ],
          ),
          if (isCurrentSDKUser)
            Row(
              children: const [
                SizedBox(width: 32),
                Icon(
                  Icons.arrow_upward,
                  color: Colors.green,
                  size: 14,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Current SDK User",
                    style: TextStyle(fontSize: 14.0),
                  ),
                ),
              ],
            ),
        ]),
      ),
    );
  }
}

Future<void> _displayCreateUserDialog(BuildContext context) async {
  final HomeBloc bloc = Provider.of(context, listen: false);
  final textFieldController = TextEditingController();
  return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('User name:'),
          content: TextField(
            onChanged: (value) {},
            controller: textFieldController,
            decoration: const InputDecoration(hintText: "User name"),
          ),
          actions: [
            TextButton(
              onPressed: () {
                bloc.createUser(textFieldController.text);
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      });
}
