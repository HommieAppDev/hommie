import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';

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
import 'listing_detail_screen.dart'; // singular "detail"
import 'user_profile_screen.dart';
import 'chat_screen.dart';
import 'compare_listings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env (for RAPIDAPI_HOST / RAPIDAPI_KEY, etc.)
  await dotenv.load(fileName: ".env");

  // Firebase init
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
        '/compare': (context) => const CompareListingsScreen(),

        // Search flow
        '/search': (context) => SearchScreen(),
        '/advanced-search': (context) => AdvancedSearchScreen(),
        // Results — support BOTH names to avoid “no generator” errors
        '/results': (context) => const SearchResultsScreen(),
        '/search-results': (context) => const SearchResultsScreen(),

        // Profiles
        '/profile': (context) => ProfileScreen(),
        '/edit-profile': (context) => EditProfileScreen(),
        '/user-profile': (context) => const UserProfileScreen(),

        // Social
        '/favorites': (context) => FavoritesScreen(),
        '/visited': (context) => VisitedPropertiesScreen(),
        '/avatar-picker': (context) => const AvatarPickerScreen(),
        '/chat': (context) => const ChatScreen(),
      },

      // For routes that need constructor args
      onGenerateRoute: (settings) {
        if (settings.name == '/listing-details') {
          final args = (settings.arguments as Map?) ?? const {};
          final listing = (args['listing'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
          return MaterialPageRoute(
            builder: (_) => ListingDetailsScreen(listing: listing),
            settings: settings,
          );
        }
        return null; // defer to `routes`
      },

      // Friendly fallback if a route slips through unregistered
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => const SearchScreen(),
        settings: settings,
      ),
    );
  }
}
