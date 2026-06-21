import 'package:go_router/go_router.dart';
import 'pages/placeholder_pages.dart';
import 'pages/explore/explore_page.dart';
import 'pages/bookmark/bookmark_page.dart';
import 'pages/novel_detail/novel_detail_page.dart';
import 'pages/volume/volume_page.dart';
import 'pages/reader/reader_page.dart';

final appRouter = GoRouter(
  initialLocation: '/explore',
  routes: [
    GoRoute(path: '/home', builder: (context, state) => const HomePage()),
    GoRoute(
      path: '/explore',
      builder: (context, state) => const ExplorePage(),
    ),
    GoRoute(
      path: '/bookmark',
      builder: (context, state) => const BookmarkPage(),
    ),
    GoRoute(path: '/account', builder: (context, state) => const AccountPage()),
    GoRoute(
      path: '/novel/:novelId',
      builder: (context, state) => NovelDetailPage(
        novelId: state.pathParameters['novelId']!,
      ),
    ),
    GoRoute(
      path: '/novel/:novelId/volume/:volumeNumber',
      builder: (context, state) => VolumePage(
        novelId: state.pathParameters['novelId']!,
        volumeNumber: int.parse(state.pathParameters['volumeNumber']!),
      ),
    ),
    GoRoute(
      path: '/novel/:novelId/volume/:volumeNumber/chapter/:chapterOrder',
      builder: (context, state) => ReaderPage(
        novelId: state.pathParameters['novelId']!,
        volumeNumber: int.parse(state.pathParameters['volumeNumber']!),
        chapterOrder: int.parse(state.pathParameters['chapterOrder']!),
      ),
    ),
  ],
);
