# - ************************************************************************************************
# - ************************************************************************************************
# - Created by:			Dan Bunyard
# - Email Address:		danodemano@gmail.com
# - Creation date:		07/31/2017
# - Modified date:		08/06/2017
# - Filename:			uploadBI.ps1
# - Description:			This script is designed to upload video recording from BlueIris to GoogleDrive
# - All files are encrypted using the key provided in the below config before being uploaded.
#
# - ************************************************************************************************
# - Dependencies:			
# - Google Drive CLI Client: https://github.com/prasmussen/gdrive (AND THE CREATED JSON FILE!!!!)
# - 7-Zip CLI (Extra): http://www.7-zip.org/download.html
# - 
# - 
# - ************************************************************************************************
# - MIT License

# - Copyright (c) 2017 Dan Bunyard

# - Permission is hereby granted, free of charge, to any person obtaining a copy
# - of this software and associated documentation files (the "Software"), to deal
# - in the Software without restriction, including without limitation the rights
# - to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# - copies of the Software, and to permit persons to whom the Software is
# - furnished to do so, subject to the following conditions:

# - The above copyright notice and this permission notice shall be included in all
# - copies or substantial portions of the Software.

# - THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# - IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# - FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# - AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# - LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# - OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# - SOFTWARE.
# - ************************************************************************************************
# - Revisions:		1.00 - Initial release
# - 				1.01 - Fixed SQL scripts to handle ' in filename
# - ************************************************************************************************
# - To do list:		[nothing]
# - ************************************************************************************************
# - ************************************************************************************************

# - ************************************************************************************************
# - ************************************************************************************************
# - User controlled variables
#$filedir = ".\toupload" #The directory we are going to encrypt/upload
$filedir = "C:\BlueIris\New"
#$filedir = "Z:\"
$tempdir = ".\temp" #The temp directory where we will store the encrypted files to upload
#$tempdir = "C:\temp"
$lockdir = ".\lock" #Where we store the lock file to prevent multiple instances running
$recurse = $true #Set to $false to only upload files in the root of the above directory
$retries = 3 #Number of times to retry the upload if it fails - after that we move on to the next file
$gdriveconfigpath = ".\.gdrive" #assuming a .grive folder in the same directory of the script
$encryption_key = "password" #randomly generate this!
$upload_directory = "dir_id" #The ID of the directory we are uploading to

# - ************************************************************************************************
# - ************************************************************************************************
# - WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING
# - ************************************************************************************************
# - UNLESS YOU KNOW WHAT YOU ARE DOING DO NOT EDIT BELOW THIS LINE
# - ************************************************************************************************
# - WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING WARNING
# - ************************************************************************************************
# - ************************************************************************************************

echo "Starting script!"

#Check if lock file already exisist
if (Test-Path "$lockdir\lock.txt") {
	#Lock file already exists - exiting!
	echo "Lock file exists - another copy is running.  Exiting!"
	exit
}

#Before continuing, create the lock file
Add-Content "$lockdir\lock.txt" $pid

echo "Getting all files from the specified directory!"

# - Get all the files in the directory listed above
if ($recurse) {
	# - Recurse if set to true
	$files = Get-ChildItem -recurse $filedir -filter "*.mp4"
}else{
	# - Otherwise only upload files in the root
	$files = Get-ChildItem $filedir -filter "*.mp4"
} #END - if ($recurse) {

#Get all the files currently in gdrive
$gdrive_files = (.\gdrive\gdrive.exe --config "$gdriveconfigpath" list --max 0 --name-width 0)

# - Loop through and encrypt/upload each file
for ($i=0; $i -lt $files.Count; $i++) {
	# - Get the file name of the current file we are working with
	$filename = $files[$i].FullName
	$filename2 = $files[$i].Name
	echo "File to be uploaded/encrypted: $filename"
	
	#See if the file has already been uploaded
	if ($gdrive_files -like "*$filename2*") { 
		echo "File already exisist!  Moving to next." 
	}else{
		# - Get the size of the file
		$filesize = (Get-Item "$filename").length
		echo "File size: $filesize"
		
		# - Get the hash of the file we are about to encrypt for comparison
		# - at a later date.  No worries about collisions as we will compare
		# - both the hash and filename.  Also since we aren't using this
		# - for anything authentication based it really doesn't matter.
		$filehash = (Get-FileHash $filename -Algorithm "SHA1").Hash
		echo "File SHA1 hash: $filehash"
		
		#Set the password to the encryption string
		$password = $encryption_key
		
		echo "Encrypting file!"

		# - The command we are going to use to encrypt the file
		#echo ".\7zip\7za.exe a -t7z -mx0 -p"$password" "$tempdir\$filename2.7z" "$filename" -mhe"
		$output = (.\7zip\7za.exe a -t7z -mx0 -p"$password" "$tempdir\$filename2.7z" "$filename" -mhe)
		#exit

		# - We should also get the filehash of the encrypted file as
		# - yet another point of reference.
		$encrypted_filehash = (Get-FileHash "$tempdir\$filename2.7z" -Algorithm "SHA1").Hash
		echo "Encrypted file SHA1 hash: $encrypted_filehash"
		
		# - Get the size of the encrypted file
		$encrypted_filesize = (Get-Item "$tempdir\$filename2.7z").length
		echo "Encrypted file size: $encrypted_filesize"
		
		# - Another note letting the user know we are uploading the file
		echo "Uploading file to Gdrive!"

		# - Upload the file to Gdrive removing it when finished
		$output = (.\gdrive\gdrive.exe --config "$gdriveconfigpath" upload --delete --parent "$upload_directory" "$tempdir\$filename2.7z")
		
		# - Need to make sure the file actually uploaded.
		# - We will retry a number of times before giving up
		# - and moving onto the next file.
		$counter = 0
		while ( ( $output -contains '*Failed*' ) -and ( $counter -lt $retries ) ) {
			# - Upload the file to Gdrive removing it when finished
			$output = (.\gdrive\gdrive.exe --config .\.gdrive upload --delete "$tempdir\$filename2.7z")
			$counter++
		} #END - while ( ( $output -contains '*Failed*' ) -and ( $counter -lt $retries ) ) {
		
		# - Check again if still failed
		if ( $output -contains '*Failed*' ) {
			# - Need to move on and NOT log this into the database
			echo "Unable to complete upload, moving on"
			
			# - Cleanup the temp file so it doesn't linger
			del "$tempdir\$filename2.7z"
		}else{
			echo "File uploaded!"
		} #END - if ( $output -contains '*Failed*' ) {
		
		echo "Moving onto next file!"
	}
} #END - for ($i=0; $i -lt $files.Count; $i++) {

#Remove the lock file
Remove-Item "$lockdir\lock.txt"

echo "Done!"
