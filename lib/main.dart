import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'avatar_picker_screen.dart';
import 'welcome_screen.dart';
import 'signup_screen.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'advanced_search_screen.dart';
import 'profile_screen.dart';
import 'edit_profile_screen.dart';
import 'favorites_screen.dart';
import 'visited_properties_screen.dart';
import 'search_results_screen.dart';
import 'listing_detail_screen.dart'; // NOTE: singular "detail" to match your file
import 'user_profile_screen.dart';
import 'chat_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const HommieApp());
}

class HommieApp extends StatelessWidget {
  const HommieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hommie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      initialRoute: '/welcome',
      routes: {
        '/': (context) => WelcomeScreen(),
        '/welcome': (context) => WelcomeScreen(),
        '/signup': (context) => SignUpScreen(),
        '/home': (context) => HomeScreen(),
        '/search': (context) => SearchScreen(),
        '/advanced-search': (context) => AdvancedSearchScreen(),
        '/profile': (context) => ProfileScreen(),
        '/edit-profile': (context) => EditProfileScreen(),
        '/visited': (context) => VisitedPropertiesScreen(),
        '/favorites': (context) => FavoritesScreen(),
        '/avatar-picker': (context) => const AvatarPickerScreen(),
        // Static route; screen reads args via ModalRoute
        '/search-results': (context) => const SearchResultsScreen(),
        '/user-profile': (context) => const UserProfileScreen(),
        '/chat': (context) => const ChatScreen(),
      },
      onGenerateRoute: (settings) {
        // Only handle routes that need constructor args here
        if (settings.name == '/listing-details') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (_) => ListingDetailsScreen(
              listing: args['listing'],
            ),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
