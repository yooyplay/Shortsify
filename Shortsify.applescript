on findFFmpeg()
	repeat with candidate in {"/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"}
		try
			do shell script "test -x " & quoted form of (candidate as string)
			return candidate as string
		end try
	end repeat
	display alert "ffmpeg not found" message "Install it with: brew install ffmpeg" as critical
	error number -128
end findFFmpeg

on convertFile(filePath)
	set ffmpeg to findFFmpeg()
	set outputPath to do shell script "f=" & quoted form of filePath & "; echo \"${f%.*}_short.${f##*.}\""
	set vf to "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black"
	set cmd to quoted form of ffmpeg & " -i " & quoted form of filePath & " -vf '" & vf & "' -c:v libx264 -crf 18 -preset fast -c:a aac -b:a 192k -movflags +faststart " & quoted form of outputPath & " && echo '' && echo '✅ Done! Saved to: " & outputPath & "'"
	tell application "Terminal"
		activate
		do script cmd
	end tell
end convertFile

on open theFiles
	repeat with aFile in theFiles
		convertFile(POSIX path of aFile)
	end repeat
end open

on run
	try
		set theFile to choose file with prompt "Choose a video to convert to 9:16 (YouTube Shorts / TikTok):"
		convertFile(POSIX path of theFile)
	on error number -128
		-- user cancelled
	end try
end run
