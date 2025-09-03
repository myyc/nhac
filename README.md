# nhac

A cross-platform navidrome/subsonic client. Pretty much everything has been developed with Claude code minus the icon (which is why it's horrible) and this README (likewise).

<div align="center"><img width="400" alt="screenshot" src="https://github.com/user-attachments/assets/5ca68ccf-78c8-497b-9369-66b2a66fb89b" /></div>

You can do the following:

* Listen to your albums
* Search in your library
* Flex your tunes on social media

It works okay and looks quite nice.

Stuff that isn't available but is planned:

* windows, macos builds - ios is harder for obvious reasons
* proper offline support and better audio caching
* keyboard navigation, there is little right now (type to search, escape to go back, spacebar to play/pause)

Stuff that isn't planned:

* playlists
* any queue that isn't the current album

# installing

Grab one of the bundles.

`apk`s are built the usual way (`flutter build apk`) and there is a `build-flatpak.sh` that needs a bit of foreplay but it does work. It probably builds in other platforms too but I haven't tested it yet.
