#!/usr/bin/perl
# Creating a Gallery of bunch of images. 
# Arpit Jain arpitjain11@gmail.com
package IkiWiki::Plugin::gallery;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "preprocess", id => "gallery", call => \&preprocess, scan => 1);
	#hook(type => "pagetemplate", id => "gallery", call => \&pagetemplate);
} #}}}

#sub pagetemplate(@){ #{{{
#	my %params=@_ ; 
#	my $template = $params{template};
#	my $page = $params{page}; 
#	my $scripts;

#   my $baseurl=IkiWiki::baseurl();
#	if($template->query(name => "gallery")){
#		my $pagetmpl=template("gallery.tmpl", blind_cache => 1); 
#		$pagetmpl->param(prototype1 => "js/prototype.js");
#		$pagetmpl->param(scriptaculous => "js/scriptaculous.js?load=effects");
#		$pagetmpl->param(lightbox => "js/lightbox.js");
#		$pagetmpl->param(lightboxcss => "css/lightbox.css");
#		$pagetmpl->param(baseurl => "$baseurl");
#		$scripts=$pagetmpl->output ; 
#	}
#	$template->param(gallery => $scripts);
#} #}}}


#Adds Required Javascripts and CSS for Gallery
#Scripts can be changed if template needs to be changed.
sub get_js() {
    my $baseurl=IkiWiki::baseurl();
	return '<script type="text/javascript" src="'.$baseurl.'js/prototype.js"></script>
	<script type="text/javascript" src="'.$baseurl.'js/scriptaculous.js?load=effects"></script>
	<script type="text/javascript" src="'.$baseurl.'js/lightbox.js"></script>
	<link rel="stylesheet" href="'.$baseurl.'css/lightbox.css" type="text/css" media="screen" />';
}

sub preprocess (@) { #{{{
	my %params=@_;

	#Set to 0 if you dont't want to put images in VCS
	my $vcs=$params{vcs} ;
	$vcs = 1 if not defined $vcs; 

	#Name of Image Directories separated by Commma
	my $imagedir = $params{imagedir} || ''; 
	
	#Decides whether the image would be rendered in the same page or another one. 
	#my $inline = $params{inline} || '0';
	#To Scan directories recursively for images or not.
	#my $recursive = $params{recursive} || '1'; 

	my $cols = $params{cols} || '3';
	my $rows = $params{rows} || '3';

	#sort=asc/desc
	my $sort = $params{sort};
	my $title = $params{title} || 'My Pictures'; 
	
	my @imagedirs = split(/,/,$imagedir);
	my $directory;
	
	#Gallery Page
	my $albumlink = "gallery/$params{page}";
	will_render($params{page}, $albumlink."/index.html"); 
	
	#Link from Album page to the page from where it was generated.
	my $linkhome = urlto($params{page},$albumlink); 

	#Gallery Details
	my $gallerylink = ''; 
	my $gallerydir; 
	
	#Source Thumbnail for gallery pointer.
	my $thumbsource = ''; 

 	my $albumtext = '<html><head>'; 
	$albumtext .= get_js(); 
	$albumtext .= '<title>'.$title.'</title></head><body><table align="center">'; 
	$albumtext .= '<tr><td align="center" colspan="'.$cols.'"><h2>'.$title.' Albums</h2></td></tr>';
	$albumtext .= '<tr><td align="center" colspan="'.$cols.'"><a href="'.$linkhome.'">Home</a></td></tr>';
	#TODO: Add next and previous links here. Add support for rows.

	my $numcols = 0;
	my $numrows = 0;
	#Generate Album Page and Gallery Pages for all Directories
	foreach $directory (@imagedirs){
		my $dir = bestdir($params{page}, $directory, $vcs) || return "[[gallery ".sprintf(gettext("Failed to Read Directory %s."), $directory)."]]"; 
		
		$gallerydir = "gallery/$params{page}/$dir"; 
		$gallerylink = "$gallerydir/gallery_1.html" ;
	 	will_render($params{page},$gallerylink) ;

		$params{'imagedir'}=$directory; 
		$params{'albumlink'} = $albumlink; 
		
		#Make gallery of images in the directory.
		$thumbsource = makeGallery(%params); 

		my $galleryurl = urlto($gallerylink,$albumlink);
		my $thumburl = urlto($thumbsource,$albumlink);
		if(!$vcs) {
			$galleryurl=~s/^(.*)\/$/$1/g;
		}
		
		if($numcols==0) { 
			$albumtext .= "<tr>";
		}
		$albumtext .= '<td><table align="center"><tr><td align="center" class="images"><a href="'.$galleryurl.'" title="'.$directory.'"><img src="'.$thumburl.'" /></a></td></tr><tr><td align="center">'.$directory.'</td></tr></table></td>';
	
		$numcols ++ ;
		if ($numcols == $cols) {
			$albumtext .= "</tr>";
			$numcols = 0 ;
		}
	}

	$albumtext .= "</table></body></html> " ; 
	#$albumtext=IkiWiki::htmlize($albumlink."/index.html","html",$mainPageText);
	writefile($albumlink."/index.html",$config{destdir},$albumtext); 
	add_depends($params{page},$albumlink."/index.html") ; 

	my $albumurl=urlto($albumlink,$params{page});
	return  '<a href="'.$albumurl.'">Link to Gallery </a> ' ; 
}#}}}

sub makeGallery (@) {#{{{
	my %params =@_; 
	my $albumlink = $params{albumlink}; 
	my $alt = $params{alt} || '';
	my $title = $params{title} || 'Pictures Gallery'; 
	my $imagedir = $params{imagedir} || ''; 
	my $thumbnailsize= $params{thumbnailsize} || '200x200';
	my $cols= $params{cols} || '3';
	my $rows= $params{rows} || '3';
	my $vcs = $params{vcs} ;  
	my $sort = $params{sort}; 
	my $exif = $params{exif} || 1;  
	my $resize = $params{resize} || '800x600' ; 
  my $to_resize =1; 
  if (defined $params{resize} and $params{resize} == "0" ) { 
    $to_resize=0; 
  } 

	$vcs = 1 if not defined $vcs;

	my $dir = bestdir($params{page}, $imagedir,$vcs) || return "[[gallery ".sprintf(gettext("Directory %s not found"), $imagedir)."]]"; 

	my ($w, $h) = ($thumbnailsize =~ /^(\d+)x(\d+)$/);
	return "[[gallery ".sprintf(gettext('Bad Thumbnail Size "%s"'), $thumbnailsize)."]]" unless (defined $w && defined $h);
	my ($iw, $ih) = ($resize =~ /^(\d+)x(\d+)$/);
	return "[[gallery ".sprintf(gettext('Bad Image Size "%s"'), $resize)."]]" unless (defined $iw && defined $ih);
	
	my $abc = opendir PICSDIR, sourcefile($dir,$vcs);
	my @image_files = grep /\.(jpe?g|gif)$/i, readdir PICSDIR;
	closedir PICSDIR;
	if($sort) { 
		if($sort eq "asc") {
			@image_files = sort (@image_files);
		} elsif($sort eq "desc") {
			@image_files = sort {$b cmp $a} (@image_files);
		}
	}

	eval q{use Image::Magick};
	error($@) if $@;
	
	my $totalImages = scalar(@image_files); 	
	my ($numcols,$numrows,$numImages) = (0,0,0);	

	my ($gallerytext, $gallerylink) ; 
	my $gallerydir = "gallery/$params{page}/$dir/";
	my $pageNo = 1; #Page Number of the gallery of a particular directory. 

	my ($im,$r, $imagefile,$imagesize, $imagedate,$imagelink,$imageoutlink); 
	my($thumblink,$thumboutlink) ;	

	foreach $imagefile (@image_files){	
		$im = Image::Magick->new;
		$imagelink = "$dir/$imagefile";
		$thumblink = "thumb/$params{page}/$dir/${w}x${h}-$imagefile"; 
		$thumboutlink= "$config{destdir}/$thumblink"; 	#Destination Thumbnail File
		my $resizedimagelink = "$dir/${iw}x${ih}-$imagefile"; 
		$imageoutlink = "$config{destdir}/$dir/${iw}x${ih}-$imagefile"; #Every image may not have this.
		
		will_render($params{page}, $thumblink); 
    if($to_resize == 1 ) { 
  		will_render($params{page}, $resizedimagelink); 
    }  
		
		if (-e $thumboutlink && -e $imageoutlink && (-M sourcefile($imagelink,$vcs) >= -M $thumboutlink) && (-M sourcefile($imagelink,$vcs) >= -M $imageoutlink)) {
			$r = $im->Read($thumboutlink);
			return "[[gallery ".sprintf(gettext("failed to read %s: %s"), $thumboutlink, $r)."]]" if $r;
			
			$r = $im->Read($imageoutlink);
			return "[[gallery ".sprintf(gettext("failed to read %s: %s"), $imageoutlink, $r)."]]" if $r;
		} else {
			$r = $im->Read(sourcefile($imagelink,$vcs)); #Read Image File. 
			return "[[gallery".sprintf(gettext("Failed to read %s: %s"), $imagelink, $r)."]]" if $r;

			my($imwidth,$imheight) = $im->Get('columns','rows');
			my @blob;
      if($to_resize == 1 ) {
			if($imwidth > $iw || $imheight > $ih) {		
				my $temp1 = $imagelink ; 
				$imagelink = "$dir/${iw}x${ih}-$imagefile"; 
				my $ir = $im->Resize(geometry => "${iw}x${ih}"); #Create Image with Changed Resolution
				return "[[gallery ".sprintf(gettext("Failed to resize: %s"), $ir)."]]" if $ir;
				if (!$params{preview}) {
					@blob = $im->ImageToBlob();
					$imagelink=IkiWiki::possibly_foolish_untaint($imagelink);
					writefile($imagelink, $config{destdir}, $blob[0], 1);
				} else {
						$imagelink= $temp1;
				}
			}
      }

			$r = $im->Resize(geometry => "${w}x${h}"); #Create Thumbnail
			return "[[gallery ".sprintf(gettext("Failed to resize: %s"), $r)."]]" if $r;
	
			# Don't actually write file in preview mode
			if (!$params{preview}) {
				@blob = $im->ImageToBlob();
				$thumblink=IkiWiki::possibly_foolish_untaint($thumblink);
				writefile($thumblink, $config{destdir}, $blob[0], 1);
			} else {
					$thumblink = $imagelink;
			}
		}
		
		add_depends($params{page},$thumblink);	
		add_depends($params{page},$imagelink); 
		
		my ($imageurl, $thumburl);
		if (! $params{preview}) {
			#Calculate relative url of imagedir from gallerydir.
			$imageurl=urlto($imagelink, $gallerydir);
			if(!$vcs) {
				$imageurl=~s/^(.*)\/$/$1/g;
			}
			$thumburl=urlto($thumblink, $gallerydir);
		} else {
			$imageurl="$config{url}/$imagelink";
			$thumburl="$config{url}/$thumblink";
		}
	
		if($numrows==0 and $numcols==0 ) {
			$gallerytext = "<html><head>"; 
			$gallerytext .= get_js();
			$gallerytext .= "<title>$imagedir Gallery</title></head><body>" ;  #ADD TITLE
			$gallerytext .= '<table align="center">';
			if(length $imagedir){
				$gallerytext.='<tr><td align="center" colspan="'.$cols.'"><h2>'.$imagedir.'</h2></td></tr>';
			}
			my $temp; 
			$gallerytext.='<tr><td align="left">'; 
			if($pageNo > 1 ) {
				$temp = $pageNo -1 ; 
				$gallerytext .= '<a href="gallery_'.$temp.'.html"><< Previous</a>' ; 
			}
			my $link = urlto($albumlink."/index.html",$gallerydir) ; 
			$gallerytext .= '</td><td align="center"><a href="'.$link.'">Home</a></td><td align="right">' ; 
			$temp = $pageNo + 1; 
			if($numImages + $rows*$cols  < $totalImages) {
				$gallerytext .= '<a href="gallery_'.$temp.'.html">Next >></a>' ; 
			}
			$gallerytext.="</td></tr>"; 
		}
		$gallerytext .= "<tr>" if(!$numcols) ; 
		$gallerytext .= '<td align="center" class="images">	<table><tr><td align="center" class="images"><a href="'.$imageurl.'" title="'; 
		
		#Get Comments from comment files
		my $commentfile = sourcefile($imagelink,$vcs) . ".comm"; 
		my $comment = $imagefile; 
		if(-e $commentfile) { 
			open(COMMENT,$commentfile) || return "[[gallery ".sprintf(gettext("File %s not found"), $commentfile)."]]"; 
			my @comments = <COMMENT>; 
			$comment = "@comments";
			close(COMMENT);
		}
		$gallerytext .= "$comment";
		
		#Get Image Exif Information
		my $image = Image::Magick->new;
		my 	($width, $height, $size, $format) = $image->Ping(sourcefile($imagelink,$vcs));
		#warn $width if $width || $height || $size || $format;
		my $info=", $width"."x".$height.", $size bytes"; 
		$gallerytext .= "$info" if $exif ;

		#Print HTML
		$gallerytext .= '" rel="lightbox[mypics]"><img src="'.$thumburl.'"/></a></td>';
		$gallerytext .= '</tr><tr><td align="center">'. $imagefile.'</td></tr></table></td>';
		$numcols++; 
		$numImages++; 
		if($numcols==$cols || $numImages == $totalImages) {
			$numcols=0; 
			$gallerytext .= "</tr>"; 
			$numrows++;
			if($numrows==$rows || $numImages == $totalImages) {
				$numrows=0;
				$gallerytext.="</table></body></html>"; 

				#Write Gallery Page here
				$gallerylink = "$gallerydir/gallery_".$pageNo.".html"; 
				will_render($params{page}, $gallerylink); 
				#$gallerytext=IkiWiki::htmlize($gallerylink,"html",$galleryPageText); 
				writefile($gallerylink,$config{destdir},$gallerytext); 
				add_depends($params{page},$gallerylink);
				$gallerytext=""; 
				$pageNo++; 
			}
		}
		undef $im ; 
		undef $image;
	}
	
	#Write loading.png and closelabel.png in Destination Image Directory.
	my (@lightboximage,@lightboxlink, @lightboxoutlink, @lightboxsourcelink); 
	$lightboximage[0] = "loading.png"; 
	$lightboximage[1] = "closelabel.png"; 
	my $basewiki = $config{underlaydir};
	my $ii;
	for($ii=0;$ii<=1;$ii++) {
		$lightboxlink[$ii]="$gallerydir/$lightboximage[$ii]";
		$lightboxoutlink[$ii] = "$config{destdir}/$lightboxlink[$ii]";
		$lightboxsourcelink[$ii] = "$basewiki/images/$lightboximage[$ii]";

		will_render($params{page},$lightboxlink[$ii]);	
		$im = Image::Magick->new;
		if (-e $lightboxoutlink[$ii]) { #Do Not write the file if already exists.
			$r = $im->Read($lightboxoutlink[$ii]);
			return "[[gallery ".sprintf(gettext("failed to read %s: %s"), $lightboxoutlink[$ii], $r)."]]" if $r;
		} else {
			$r = $im->Read($lightboxsourcelink[$ii]); #Read Image File. 
			return "[[gallery".sprintf(gettext("Failed to read %s: %s"), $lightboxsourcelink[$ii], $r)."]]" if $r;

			# Don't actually write file in preview mode
			if (! $params{preview}) {
				my @blob = $im->ImageToBlob();
				$lightboxlink[$ii]=IkiWiki::possibly_foolish_untaint($lightboxlink[$ii]);
				writefile($lightboxlink[$ii], $config{destdir}, $blob[0], 1);
			}
		}
		add_depends($params{page},$lightboxlink[$ii]);	
		undef $im;
	}
		
	return $thumblink;
} #}}}


sub sourcefile($$) { #{{{
	my $dir=shift;
	my $vcs=shift;
	if($vcs) {
		return srcfile($dir); 
	} else {
		if($dir =~ /^\//){ #Absolute Path. 
			return $dir; 
		}else{ #Relative path to destdir
			return "$config{destdir}/$dir" ; 
		}
	}
	return 0; 
} #}}}

sub bestdir ($$$) { #{{{
	my $page=shift;
	my $link=shift;
	my $vcs = shift; 
	my $destdir=$config{destdir};
	my $dir="";

	if(!$vcs){
		if($link =~ /^\//){ #If user gives absolute path. Allow it afterwards. 
			($dir) = ($link=~ /^$destdir\/(.*)$/);  #Check whether it is defined or not. 
			if(not $dir) { #Directory not in Ikiwiki's final Tree. Does it need to be ??
				return 0; 
			}
		}else{
			$dir=$link; #If user gives relative path.
		}
		if(-d "$destdir/$dir"){
			return "$dir";
		}
		return "";
	}


	my $cwd=$page;

	if ($link=~s/^\/+//) {
		$cwd="";

	}
	do {
		my $l=$cwd;
		$l.="/" if length $l;
		$l.=$link;
		if (-d "$config{srcdir}/$l") {
			return $l;
		}
	} while $cwd=~s!/?[^/]+$!!;
	
	if (length $config{userdir}) {
		my $l = "$config{userdir}/".lc($link);

		if (-d $l) {
			return $l;
		}
	}
	return "";
} #}}}

1
