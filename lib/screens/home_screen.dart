import 'package:flutter/material.dart';
import 'package:flutter_application_helpvrywhere/screens/request_map_screen.dart';
import 'package:flutter_application_helpvrywhere/screens/request_creation_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text("good morning", style: TextStyle(fontSize: 15)),
            Text("Seonwoo", style: TextStyle(fontSize: 25)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: CircleAvatar(backgroundColor: Colors.blueGrey),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          spacing: 10,
          children: [
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RequestMapScreen(),
                        ),
                      );
                    },
                    child: Container(
                      height: 135,
                      padding: EdgeInsets.all(25),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Color.fromARGB(249, 255, 247, 153),
                      ),
                      child: Text(
                        "Find nearby requests",
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {},
                    child: Container(
                      height: 135,
                      padding: EdgeInsets.all(25),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Color.fromARGB(228, 148, 223, 255),
                      ),
                      child: Text(
                        "AI tech support",
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: Container(
                    height: 135,
                    padding: EdgeInsets.all(25),
                    alignment: Alignment.bottomLeft,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Color.fromARGB(236, 205, 255, 144),
                    ),
                    child: Text(
                      "My help history",
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RequestCreationScreen(),
                        ),
                      );
                    },
                    child: Container(
                      height: 135,
                      padding: EdgeInsets.all(25),
                      alignment: Alignment.bottomLeft,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Color.fromARGB(139, 219, 165, 255),
                      ),
                      child: Text(
                        "Create a request",
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
