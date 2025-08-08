import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'signup_screen.dart';
import 'login_screen.dart';
import 'search_screen.dart';
import 'advanced_search_screen.dart';
import 'welcome_screen.dart';
import 'search_results_screen.dart';
import 'profile_screen.dart';
import 'edit_profile_screen.dart';
import 'favorites_screen.dart';
import 'visited_properties_screen.dart';
import 'upload_listings.dart'; 
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const HommieApp());

  // 🔁 TEMPORARY: Upload sample listings AFTER app starts
  Future.delayed(Duration.zero, () async {
    await uploadSampleListings();
  });
}

class HommieApp extends StatelessWidget {
  const HommieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hommie',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      initialRoute: '/welcome',
      routes: {
        '/welcome': (context) => WelcomeScreen(), 
        '/signup': (context) => SignUpScreen(),
        '/login': (context) => LogInScreen(),
        '/search': (context) => SearchScreen(),
        '/advanced-search': (context) => AdvancedSearchScreen(),
        '/profile': (context) => ProfileScreen(),
        '/edit-profile': (context) => EditProfileScreen(),
        '/visited': (context) => VisitedPropertiesScreen(),
        '/favorites': (context) => FavoritesScreen(),
        '/home': (context) => HomeScreen(),  
        '/search-results': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;

          return SearchResultsScreen(
            cityOrZip: args?['query'],
            radiusMiles: args?['radius'],
            price: args?['price'],
            beds: args?['beds'],
            baths: args?['baths'],
          );
        },
      },
    );
  }
}
