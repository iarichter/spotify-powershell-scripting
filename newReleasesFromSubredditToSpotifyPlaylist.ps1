<#
IAR's subreddit to Spotify AutoPlaylist Script. 
V1 : 2024-03-27

Dependancies: 
This was all written and tested for PowerShell 7 in VSCode

REQUIRED: lennyomg's Spotify-PowerShell module 
Sourced from GitHub: https://github.com/lennyomg/Spotify-PowerShell

REQUIRED: a Spotify Developer App to get an access token and use the various Spotify APIs
Start here: https://developer.spotify.com/documentation/web-api/tutorials/getting-started
#>

## allow for the unsigned Spotify Powershell module to run
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

<#
#custom functions below
#>
Function Get-SpotifyAlbumData ([string]$inputAlbumURL) {
    $albumID = $inputAlbumURL.split("?")[0] -replace "https.*?album/", ""
    $albumResponse = Get-SpotifyAlbum -AlbumId $albumID
    Write-Host "Found album for URL! Album name:" $albumResponse.name "| Artists:" $albumResponse.artists.name "| Release Date:" $albumResponse.release_date -BackgroundColor White -ForegroundColor Black -NoNewline
    Write-Host ""
    $global:spotifyReleaseDate = Get-Date $albumResponse.release_date
    $trackIDs = $albumResponse.tracks.items.id
    $global:tracksArray = @()
    foreach ($track in $trackIDs) {
        $global:tracksArray += $track
    }
    Write-Host $trackIDs.count "tracks found for the album" -BackgroundColor White -ForegroundColor Black -NoNewline
    Write-Host ""
}

Function Get-SpotifyTrackData ($inputTrackURL) {
    $global:tracksArray =@()
    $global:tracksArray = $inputTrackURL.split("?")[0] -replace "https.*?track/", ""
    $trackResponse = Get-SpotifyTrack -TrackID $global:tracksArray
    Write-Host "Found track for URL! Album name:" $trackResponse.name "| Artists:" $trackResponse.artists.name "| Release Date:" $trackResponse.album.release_date -BackgroundColor White -ForegroundColor Black -NoNewline
    Write-Host ""
    $global:spotifyReleaseDate = Get-Date $trackResponse.album.release_date
}


### END FUNCTIONS

<# this commented out section was used to get my access token. You should only need to run in once and after that use the Update-SpotifyAccessToken function to refresh it
## Get the ClientID value from the Spotify app you created.
$spotifyClientID = "{put ID here}"
New-SpotifyAccessToken -ClientId $spotifyClientID
## Which returns an auth code which you use this way.
$spotifyAuthCode = "{put auth code here}"
New-SpotifyAccessToken -AuthorizationCode $spotifyAuthCode
#>

<# This is YOUR personal Spotify ID. This is used to create a new playlist under your account.
To find your ID navigate to your profile and find some sort of "Share profile"/"Copy link to profile" option (probably under a tripple dot menu)
The copied url will have your uinque ID value after the "...user/{bunch of numbers}"
E.g. my account is: https://open.spotify.com/user/1297826102 
So the value I use below is "1297826102"
#>
$mySpotifyId = ""
## get a fresh token cause it's probably expired since last run
Write-Host "Getting Fresh Spotify Authorization Token"
Update-SpotifyAccessToken

## input a Subreddit you want to return Spotify URLs from
$subReddit = Read-Host "What subreddit do you want to make a playlist from? (exclude the 'r/' and just put the name between slashes in the url)"

<# use $minUpVoteRation to potenentially exclude low quality posts.
Range is 0-1. '0' will give you all posts, '1' will give you the fewest.
From VERY brief testing on a single subreddit I observed most spam posts getting filtered out around 0.75 so that's my default, but of course results will vary over time and between subreddits.
#>
$minUpvoteRatio = 0.75
<# use $releaseDateRange to filter out older music from getting added to playlists. 
Since I usually just want NEW music the default is 180 days or newer, but adjust to your liking.  
#>
$releaseDateRange = 65


Write-Host "Getting post With Spotify Links"
$SpotifyPostsArray = @()
$redditContinue = $true
$redditAfterString = ""
$redditAPICalls = 1
$skippedPosts = 0
##logic for getting list of reddit posts, then checking if the last one is still not old enough since last run, and looping again
while ($redditContinue) {
    write-host "Processing API call #"$redditAPICalls
    $redditAPICalls++
    $redditURI = "https://www.reddit.com/search.json?q=subreddit%3A" + $subReddit + "+site%3Aspotify.com&t=year&limit=99&sort=new" + $redditAfterString
    Write-Host "Making API call:"$redditURI
    $RedditPosts = Invoke-RestMethod -Method GET -URI $redditURI
    if ($null -eq $redditPosts.data.after) {
        $redditContinue = $false
    }
    else { $redditAfterString = "&after=" + $redditPosts.data.after }

    foreach ($post in $RedditPosts.data.children) {
        #if there's a ? in the URL trim that off and everything after it
        if ($post.data.upvote_ratio -gt $minUpvoteRatio) {
        $url = $post.data.URL -replace "(.*?)\?.*", '$1'
        $createdTimeStamp = (Get-Date 01.01.1970).AddSeconds($post.data.created)
        $createdDate = $createdTimeStamp.ToString("yyyy-MM-dd")
        $upvotes = $post.data.ups
        $upvoteRatio = $post.data.upvote_ratio
        $spotifyPost = [PSCustomObject]@{
            URL        = $url
            DatePosted = $createdDate
            Upvotes = $upvotes
            UpvoteRatio = $upvoteRatio
        }
        $SpotifyPostsArray += $spotifyPost}

        else {
            $skippedPosts++
            Write-Host "Skipping post:" $post.data.title "| Upvote ratio too low at" $post.data.upvote_ratio
            Continue
        }
    }
}

$urlCount = $SpotifyPostsArray.count
Write-host $urlCount "Spotify urls found on Reddit with an upvote ratio above " $minUpvoteRatio
Write-host $skippedPosts "Reddit posts skipped due to too low of an upvote ratio" 
$today = Get-Date
$oldestReleaseDate = $today.AddDays(-$releaseDateRange)

#create new playlist for these URLs
$playlistName = "New releases | r/" + $subReddit +" | "+$today.ToString("yyyy-MM-dd") 
$newPlaylist = New-SpotifyPlaylist -UserId $mySpotifyId -Name $playlistName
## Now process the list of Spotify URLs
Write-Host "Parsing list of URLs"
foreach ($spotifyPostItem in $SpotifyPostsArray) {
        if ($spotifyPostItem.url -like "*album*") {
            Get-SpotifyAlbumData($spotifyPostItem.url)
        }
        elseif ($spotifyPostItem.url -like "*track*") {
            Get-SpotifyTrackData($spotifyPostItem.url)
        }
        elseif ($spotifyPostItem.url -like "*playlist*") {
            Write-Host "Skipping playlist"
            Continue
        }
        else {
            Write-Host "Something wrong with the URL from Reddit:" $spotifyPostItem.url -BackgroundColor DarkBlue -ForegroundColor Red
            Continue
        }
        if ($global:spotifyReleaseDate -lt $oldestReleaseDate) {
            Write-Host "Release date is older than" $releaseDateRange "days. Skipping URL."
            Continue
        }
        $global:newPlaylistTracksArray = @()
        $playlistTracks = Get-SpotifyPlaylistTracks -PlaylistId $newPlaylist.id
        $global:newPlaylistTracksArray += $playlistTracks.id
        #Remove any tracks from the link that are already on the corresponding playlist so we don't add duplicates
        $global:cleanedTracksArray = [array]($global:tracksArray | Where-Object { $global:newPlaylistTracksArray -notcontains $_ })
        if ($global:cleanedTracksArray.count -eq 0) {
            Write-host "No tracks to add after deduplicating list"
            Continue
        }
        else {
        #Add all new tracks to the correct Firehouse Fresh playlist
        Add-SpotifyPlaylistTracks -PlaylistId $newPlaylist.id -TrackId $global:cleanedTracksArray
        Write-Host "Adding" $global:cleanedTracksArray.count "track(s) to playlist"  -BackgroundColor Blue -ForegroundColor White -NoNewline
        Write-Host ""
        }
}