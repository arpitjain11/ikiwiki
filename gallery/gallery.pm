##!/usr/bin/perl
# Creating a Gallery of bunch of images. 
# Arpit Jain arpitjain11@ozoneball.com
package IkiWiki::Plugin::gallery;

use warnings;
use strict;
use IkiWiki 2.00;

sub import { #{{{
	hook(type => "preprocess", id => "gallery", call => \&preprocess);
	hook(type => "pagetemplate", id => "gallery", call => \&pagetemplate);
} #}}}

sub pagetemplate(@){ #{{{
	my %params=@_ ; 
	my $template = $params{template};
	my $page = $params{page}; 
	my $scripts;

	if($template->query(name => "gallery")){
		my $pagetmpl=template("gallery.tmpl", blind_cache => 1); 
		$pagetmpl->param(prototype1 => "prototype.js");
		$pagetmpl->param(scriptaculous => "scriptaculous.js?load=effects");
		$pagetmpl->param(lightbox => "lightbox.js");
		$pagetmpl->param(lightboxcss => "css/lightbox.css");
		$pagetmpl->param(baseurl => "$config{url}/");
		$scripts=$pagetmpl->output ; 
	}
	$template->param(gallery => $scripts);
} #}}}

sub preprocess (@) { #{{{
	my %params=@_;
	
	my $alt = $params{alt} || '';
	my $title = $params{title} || '';
	my $imagedir = $params{imagedir} || '';
	my $thumbnailsize= $params{thumbnailsize} || '200x200';
	my $cols= $params{cols} || '3';
	my $name = $params{name} || '1';
	
	my $dir = bestdir($params{page}, $imagedir) || return "[[gallery ".sprintf(gettext("Directory %s not found"), $imagedir)."]]"; 

	my ($w, $h) = ($thumbnailsize =~ /^(\d+)x(\d+)$/);
	return "[[gallery ".sprintf(gettext('bad thumbnail size "%s"'), $thumbnailsize)."]]" unless (defined $w && defined $h);
	
	opendir PICSDIR, srcfile($dir);
	my @image_files = grep /\.(jpg|png|gif)$/, readdir PICSDIR;
	closedir PICSDIR;

	eval q{use Image::Magick};
	error($@) if $@;
	
	my $numfiles = scalar(@image_files); 	
	my $numcols=0;	

	my $tosend='<table align="center">';
	if(length $title){
	$tosend.="<tr><td align=\"center\" colspan=\"$cols\"><h2>$title</h2></td></tr>";
	}

	my ($imagefile,$im,$r);

	foreach $imagefile (@image_files){		
		$im = Image::Magick->new;
		my $imagelink = "$dir/$imagefile"; #Source Image File
		my $thumblink = "$dir/${w}x${h}-$imagefile";  #Destination Thumbnail File
		my $thumboutlink= "$config{destdir}/$thumblink" ; #Destination Image File
		
		will_render($params{page}, $thumblink); 
		
		if (-e $thumboutlink && (-M srcfile($imagelink) >= -M $thumboutlink)) {##Do Not Create Thumbnail if already exists.
			$r = $im->Read($thumboutlink);
			return "[[gallery ".sprintf(gettext("failed to read %s: %s"), $thumboutlink, $r)."]]" if $r;
		} else {
			$r = $im->Read(srcfile($imagelink)); #Read Image File. 
			return "[[gallery".sprintf(gettext("Failed to read %s: %s"), $imagelink, $r)."]]" if $r;
			
			$r = $im->Resize(geometry => "${w}x${h}"); #Create Thumbnail
			return "[[gallery ".sprintf(gettext("Failed to resize: %s"), $r)."]]" if $r;
	
			# Don't actually write file in preview mode
			if (! $params{preview}) {
				my @blob = $im->ImageToBlob();
				$thumblink=Ikiwiki::possibly_foolish_untaint($thumblink);
				writefile($thumblink, $config{destdir}, $blob[0], 1);
			}else {
					$thumblink = $imagelink;
			}
		}
		
		add_depends($params{page},$thumblink);	
		add_depends($params{page},$imagelink); 
	
		my ($imageurl, $thumburl);
		if (! $params{preview}) {
			$imageurl=urlto($imagelink, $params{destpage});
			$thumburl=urlto($thumblink, $params{destpage});
		} else {
			$imageurl="$config{url}/$imagelink";
			$thumburl="$config{url}/$thumblink";
		}
		undef $im ; 
		if(!$numcols){
		$tosend.="<tr>";
		}
		if($name==1){
		$tosend.="<td align=\"center\" class=\"images\"><table><tr>";
		}
		$tosend.= "<td align=\"center\" class=\"images\"><a href=\"$imageurl\" title=\"$imagefile\" rel=\"lightbox[mypics]\"><img src=\"" .$thumburl."\"/></a></td>";
		if($name==1){
		$tosend.="</tr><tr><td align=\"center\">$imagefile</td></tr></table></td>";
		}
		$numcols++; 
		if($numcols==$cols) {
		$numcols=0; 
		$tosend .= "</tr>"; 
		}
	}
	$tosend.="</table>";
	
	return $tosend; 
} #}}}

sub bestdir ($$) { #{{{
	my $page=shift;
	my $link=shift;
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
