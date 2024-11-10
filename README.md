This is pre-release staging of qPack code. Use with extreme caution!

qPack is a set of tools designed for Audiobookshelf users who are comfortable on the Linux CLI. It currently makes no attempt to retrieve descriptions or any other information except what it assumes from Audiobookshelf's behavior.  There are some ways to tweak settings for some other users.

Currently staged:
- Alpha framework
- qPackConfig: UI-from-CLI configuration tool
- qPackRename: Rename {title}.mp3 files generated by ABS. Designed to be
    very friendly for adding and changing naming templates. Check out the
    --show-samples option before previewing full output. Use --dry-run with
    new shows. Show creators sometimes change metadata THEY populate.


Audiobookshelf warning:
Audiobookshelf, when presented with a second publication of the same title, faces a filename collision. It avoids this by adding the guid as a suffix to subsequent episodes with a title that matches one already in the directory. 
The title being a duplicate does not mean the episode is. Some podcasts publish multiple episodes with the same title. One example I ran across was when Freakonomics did a 5-year-later update on an episode. Audiobookshelf was unable to use its normal title.mp3 so appended an id suffix. Unfortunately, the script does not (yet?) remove this suffix, but it should be possible to test for with reasonable confidence with a regex. The reason I have not done is that I have also seen this behavior when a podcast episode is re-uploaded with a very minor change hours after it was first published without removing the first episode from the RSS feed. I letting them stick out because I'm checking them out on a case-by-case basis. It's usually a matter of removing the suffix and letting the date speak for itself because the title was reused.

Installation and usage:

1. Clone this git
2. Execute qPackConfig.sh
3. Maximize your terminal and try qPackRename.sh --show-samples "Some Audiobookshelf Podcast folder"
4. Try qPackRename.sh -f <your chosen index #> "Podcast folder" --dry-run to get a full preview of proposed new names
5. Run qPackRename without --dry-run when you are satisfied.
6. Rinse and repeat from step 3 or 4, always beginning with --dry-run only
