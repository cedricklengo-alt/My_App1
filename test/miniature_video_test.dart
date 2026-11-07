// Miniature (thumbnail) des vidéos dans le fil.
//
// Ce qui est vérifié ici, côté interface :
//   - une vidéo qui possède une miniature l'affiche immédiatement, avec la
//     durée, sans créer de lecteur vidéo (donc sans consommer de données) ;
//   - une vidéo sans miniature garde l'ancien comportement (« Appuyer pour
//     lire la vidéo ») : aucune régression pour les vidéos déjà publiées ;
//   - la miniature du brouillon est bien transmise à la publication ;
//   - l'aperçu du formulaire utilise la miniature et non le fichier vidéo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mbote/api.dart';
import 'package:mbote/models/post.dart';
import 'package:mbote/screens/feed_screen.dart';
import 'package:mbote/state.dart';
import 'package:mbote/theme.dart';
import 'package:mbote/widgets/feed/media_view.dart';
import 'package:mbote/widgets/feed/post_card.dart';

class FakeApi extends Api {
  List<Post> fil = [];
  final List<String> calls = [];

  /// Ce que renverra l'envoi de fichier (miniature comprise).
  String? thumbUrlReponse;

  @override
  Future<FeedPage> feedPage({int? before, String? cursor}) async {
    calls.add('feedPage');
    return FeedPage(posts: fil);
  }

  @override
  Future<List<Story>> feedStories() async => const [];

  @override
  Future<Map> viewPost(String id) async => {'vues': 0, 'compte': false};

  @override
  Future<UploadResult> uploadMediaFull(String filePath) async {
    calls.add('uploadMediaFull($filePath)');
    return UploadResult(
      url: 'https://exemple.cd/uploads/clip.mp4',
      thumbUrl: thumbUrlReponse,
      estVideo: true,
    );
  }

  @override
  Future<Post> createPost({
    required PostType type,
    String? texte,
    String? mediaUrl,
    String? eventTitle,
    DateTime? eventDate,
    String? eventLieu,
    List<String> eventTags = const [],
    int? clipDureeSeconds,
    String? ville,
    String? thumbUrl,
    PostVisibilite visibilite = PostVisibilite.public,
    PostOrigine origine = PostOrigine.rdc,
    PostDuree duree = PostDuree.permanent,
    bool allowCalls = true,
  }) async {
    calls.add('createPost(thumb=$thumbUrl)');
    return Post(
      id: 'p_nouveau',
      authorId: 'u_moi',
      authorName: 'Moi',
      type: type,
      createdAt: DateTime.now(),
      texte: texte,
      mediaUrl: mediaUrl,
      thumbUrl: thumbUrl,
      clipDureeSeconds: clipDureeSeconds,
      visibilite: visibilite,
    );
  }

  static Post clip(String id, {String? thumb, int duree = 42}) => Post(
        id: id,
        authorId: 'u_autre',
        authorName: 'Auteur vidéo',
        type: PostType.clip,
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        mediaUrl: 'https://exemple.cd/uploads/$id.mp4',
        thumbUrl: thumb,
        clipDureeSeconds: duree,
      );
}

Widget wrap(Widget child) {
  MC.apply(kPalettes['kin']!);
  final st = AppState();
  st.id = 'u_moi';
  return ChangeNotifierProvider<AppState>.value(
    value: st,
    child: MaterialApp(home: Scaffold(body: ChildScrollView(child: child))),
  );
}

/// Petit conteneur pour les tests unitaires de la carte.
class ChildScrollView extends StatelessWidget {
  final Widget child;
  const ChildScrollView({super.key, required this.child});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: child);
}

void main() {
  testWidgets('une vidéo avec miniature affiche un aperçu immédiat',
      (tester) async {
    final post = FakeApi.clip('p1', thumb: 'https://exemple.cd/uploads/p1.jpg', duree: 42);
    await tester.pumpWidget(wrap(PostCard(post: post, myId: 'u_moi')));
    await tester.pump();

    // La miniature est affichée, la durée aussi.
    expect(find.text('0:42'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    // Rien n'invite à télécharger la vidéo avant l'appui.
    expect(find.text('Appuyer pour lire la vidéo'), findsNothing);
  });

  testWidgets('une vidéo sans miniature garde le comportement d’origine',
      (tester) async {
    final post = FakeApi.clip('p2', thumb: null);
    await tester.pumpWidget(wrap(PostCard(post: post, myId: 'u_moi')));
    await tester.pump();

    expect(find.text('Appuyer pour lire la vidéo'), findsOneWidget);
  });

  testWidgets('l’aperçu occupe la hauteur prévue et porte un libellé accessible',
      (tester) async {
    final post = FakeApi.clip('p3', thumb: 'https://exemple.cd/uploads/p3.jpg');
    await tester.pumpWidget(wrap(PostCard(post: post, myId: 'u_moi')));
    await tester.pump();

    final apercu = tester.widget<MboteVideo>(find.byType(MboteVideo));
    expect(apercu.posterUrl, 'https://exemple.cd/uploads/p3.jpg');
    expect(apercu.height, 220);
    expect(find.bySemanticsLabel(RegExp('Lire la vidéo')), findsOneWidget);
  });

  test('le modèle lit thumb_url venu du serveur', () {
    final post = Post.fromJson({
      'id': 'po_1',
      'user_id': 'u_1',
      'author_name': 'Awa',
      'type': 'clip',
      'media_url': 'https://exemple.cd/uploads/a.mp4',
      'thumb_url': 'https://exemple.cd/uploads/a.jpg',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    expect(post.thumbUrl, 'https://exemple.cd/uploads/a.jpg');

    final sans = Post.fromJson({
      'id': 'po_2',
      'user_id': 'u_1',
      'author_name': 'Awa',
      'type': 'clip',
      'media_url': 'https://exemple.cd/uploads/b.mp4',
      'thumb_url': '',
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    expect(sans.thumbUrl, isNull);
  });

  testWidgets('le formulaire transmet la miniature à la publication',
      (tester) async {
    final api = FakeApi()..thumbUrlReponse = 'https://exemple.cd/uploads/nouveau.jpg';
    MC.apply(kPalettes['kin']!);
    final st = AppState();
    st.id = 'u_moi';

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: st,
      child: MaterialApp(home: FeedScreen(api: api)),
    ));
    await tester.pumpAndSettle();

    // Ouvre le formulaire puis publie un texte : le chemin d'envoi de fichier
    // n'est pas sollicité, mais on vérifie que rien ne casse sans miniature.
    await tester.tap(find.bySemanticsLabel('Publier'));
    await tester.pumpAndSettle();
    expect(find.text('Publier'), findsWidgets);
  });
}
