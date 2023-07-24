import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_google_drive_1/secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as ga;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:google_sign_in/google_sign_in.dart' as signIn;
import 'package:url_launcher/url_launcher.dart';

const _clientId =
    "293170462422-tl2bpb90pas1vb8a43mq6ma03c8340il.apps.googleusercontent.com";
const _scopes = ['https://www.googleapis.com/auth/drive.file'];

class GoogleDrive {
  final storage = SecureStorage();
  //Get Authenticated Http Client
  Future<http.Client> getHttpClient() async {
    //Get Credentials
    var credentials = await storage.getCredentials();
    if (credentials == null) {
      //Needs user authentication
      var authClient =
          await clientViaUserConsent(ClientId(_clientId), _scopes, (url) {
        //Open Url in Browser
        launch(url);
      });
      //Save Credentials
      await storage.saveCredentials(authClient.credentials.accessToken,
          authClient.credentials.refreshToken!);
      return authClient;
    } else {
      print(credentials["expiry"]);
      //Already authenticated
      return authenticatedClient(
          http.Client(),
          AccessCredentials(
              AccessToken(credentials["type"], credentials["data"],
                  DateTime.tryParse(credentials["expiry"])!),
              credentials["refreshToken"],
              _scopes));
    }
  }

// check if the directory forlder is already available in drive , if available return its id
// if not available create a folder in drive and return id
//   if not able to create id then it means user authetication has failed
  Future<String?> _getFolderId(ga.DriveApi driveApi) async {
    final mimeType = "application/vnd.google-apps.folder";
    String folderName = "personalDiaryBackup";

    try {
      final found = await driveApi.files.list(
        q: "mimeType = '$mimeType' and name = '$folderName'",
        $fields: "files(id, name)",
      );
      final files = found.files;
      debugPrint("files : ${files}");
      if (files == null) {
        print("Sign-in first Error");
        return null;
      }

      // The folder already exists
      if (files.isNotEmpty) {
        return files.first.id;
      }

      // Create a folder
      ga.File folder = ga.File();
      folder.name = folderName;
      folder.mimeType = mimeType;
      final folderCreation = await driveApi.files.create(folder);
      print("Folder ID: ${folderCreation.id}");

      return folderCreation.id;
    } catch (e) {
      print(e);
      return null;
    }
  }

  uploadFileToGoogleDrive(
      File file, signIn.GoogleSignInAccount? account) async {
    final authHeaders = await account!.authHeaders;
    final authenticateClient = GoogleAuthClient(authHeaders);
    debugPrint("void upload");
    // var client = await getHttpClient();
    var drive = ga.DriveApi(authenticateClient);
    debugPrint("drive : ${drive}");
    String? folderId = await _getFolderId(drive);
    debugPrint("folder id ${folderId}");
    if (folderId == null) {
      debugPrint("Sign-in first Error");
    } else {
      ga.File fileToUpload = ga.File();
      fileToUpload.parents = [folderId];
      fileToUpload.name = p.basename(file.absolute.path);
      var response = await drive.files.create(
        fileToUpload,
        uploadMedia: ga.Media(file.openRead(), file.lengthSync()),
      );
      debugPrint("response : ${response.id}");
      debugPrint("authenticateClient : ${authenticateClient._headers}");
      var id = response.id;
      var url = Uri.parse(
          "https://www.googleapis.com/drive/v3/files/$id?fields=webContentLink");
      var res = await http.get(url, headers: authenticateClient._headers);
      debugPrint("res : ${res.body}");
    }
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;

  final http.Client _client = new http.Client();

  GoogleAuthClient(this._headers);

  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}
