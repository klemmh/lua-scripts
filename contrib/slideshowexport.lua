--[[
  Slideshow plugin for darktable 2.4.X

  copyright (c) 2018  Holger Klemm
  
  darktable is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.
  
  darktable is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
  
  You should have received a copy of the GNU General Public License
  along with darktable.  If not, see <http://www.gnu.org/licenses/>.
]]

--[[
Version 1.0. for darktable 2.4.X

Depends:
- MELT
- MLT with ffmpeg or avlib support (mpeg2video, mpeg4, libx264, libx265)
- IMAGEMAGICK
- CORE UTILITIES (rm, mv, tr...)
   
   
Known bugs:   
- 

Change report:
- First release
   

Info workflow:
- select the images for the slideshow
- click export selected -> slideshow video
- enter the title
- change the paramteres if you like
- enter the author
- select the target directory
- enter the filename without suffix and white spaces
- enter the image hight (HDTV = 1080, UHD TV = 2160), width=0
- click export and wait
   
ADDITIONAL SOFTWARE NEEDED FOR THIS SCRIPT


USAGE
* require this file from your main luarc config file.

This plugin will add the new export modul "slideshow video".
]]

local dt = require "darktable"
local gettext = dt.gettext

-- only tested with LUA API version 5.0.0 (darktable 2.4.X)
dt.configuration.check_version(...,{4,0,0},{5,0,0})
dt.print_error("Slideshow export plugin version 1.0.0 loaded") 

-- Tell gettext where to find the .mo file translating messages for a particular domain
gettext.bindtextdomain("slideshowexport",dt.configuration.config_dir.."/lua/")

local function _(msgid)
    return gettext.dgettext("slideshowexport", msgid)
end

-- command variables
slideshowexport_homepath=os.getenv("HOME")
slideshowexport_local_tmp_path=slideshowexport_homepath.."/.local/tmp"
slideshowexport_darktable_tmpdir=dt.configuration.tmp_dir
slideshowexport_video_filename=""

slideshowexport_play_time=0
slideshowexport_mlv_support=false
slideshowexport_number_of_images=0
slideshowexport_cmd_format=""
slideshowexport_images_to_process =""
slideshowexport_profile=""
slideshowexport_codec=""
slideshowexport_filename_suffix=""
slideshowexport_extra_long_blackframe=6 --6 sec.
slideshowexport_blackframe=6 --6 sec.        
slideshowexport_framerates=0
slideshowexport_black1_frames=0
slideshowexport_title_frames=0
slideshowexport_black2_frames=0
slideshowexport_image_frames=0
slideshowexport_copyright_frames=0
slideshowexport_cross_frames=0
slideshowexport_vb_quality=0
slideshowexport_qscale_quality=0

-- CREATE SLIDESHOW DEFAULT VALUES
if (dt.preferences.read("slideshowexport",  "selected_video_resolution", "integer") == 0) then
    dt.preferences.write("slideshowexport", "extra_long_black_frame", "bool", false)
    dt.preferences.write("slideshowexport", "selected_font_size_title", "integer", 5)
    dt.preferences.write("slideshowexport", "selected_title_time", "integer", 10)
    dt.preferences.write("slideshowexport", "selected_display_time", "integer", 15)
    dt.preferences.write("slideshowexport", "selected_blending_time", "integer", 3)
    dt.preferences.write("slideshowexport", "selected_font_size_copyright", "integer", 5)
    dt.preferences.write("slideshowexport", "selected_video_resolution", "integer", 2)
    dt.preferences.write("slideshowexport", "selected_video_format", "integer", 1)
    dt.preferences.write("slideshowexport", "selected_video_framerate", "integer", 2)
    dt.preferences.write("slideshowexport", "selected_video_bitrate", "integer", 5)
    dt.preferences.write("slideshowexport", "selected_video_quality", "integer", 5)
    dt.preferences.write("slideshowexport", "sensitive_video_bitrate", "bool", false)
    dt.preferences.write("slideshowexport", "sensitive_video_quality", "bool", true)
end

-- GLOBAL CHECK FUNCTIONS

local function truncate(x)
      return x<0 and math.ceil(x) or math.floor(x)
end


local function GetFileSuffix(path)
  return path:match("^.+(%..+)$")
end

local function checkIfBinExists(bin)
  local handle = io.popen("which "..bin)
  local result = handle:read()
  local ret
  handle:close()
  if (result) then
    ret = true
  else
    ret = false
  end


  return ret
end

local function checkIfFileExists(name)
   local f=io.open(""..name.."","r")
   if f~=nil then 
       io.close(f) 
       return true 
   else 
       return false 
   end
end



-- SLIDESHOW GUI

local slideshowexport_label_title_sequence_options= dt.new_widget("label")
{
     label = _('title sequence options'),
     ellipsize = "start",
     halign = "end"
}

local slideshowexport_label_line1= dt.new_widget("label")
{
     label = "_______________________________________________",
     ellipsize = "start",
     halign = "end"
}

slideshowexport_check_button_black_frame = dt.new_widget("check_button")
{
    label = _('extra long black frame'), 
    value = dt.preferences.read("slideshowexport", "extra_long_black_frame", "bool"),
    tooltip =_('Some A/V devices have a long switching time and the title may not be displayed. This feature inserts a long black section befor the title sequence, allowing you to display the title.'), 
    clicked_callback = function(extra_long_black_frame)   
        if (extra_long_black_frame.value) then
           dt.preferences.write("slideshowexport", "extra_long_black_frame", "bool", true)
        else
           dt.preferences.write("slideshowexport", "extra_long_black_frame", "bool", false)
        end
    end,
    reset_callback = function(self_button_black_frame)
       self_button_black_frame.value = false
       dt.preferences.write("slideshowexport", "extra_long_black_frame", "bool", false)
    end
}



local slideshowexport_label_title= dt.new_widget("label")
{
     label = _('slideshow title:'),
     ellipsize = "start",
     halign = "start"
}


slideshowexport_entry_title = dt.new_widget("entry")
{
    text = _('enter the slideshow title'), 
    sensitive = true,
    is_password = true,
    editable = true,
    tooltip = _('enter your slideshow title'),
    reset_callback = function(self_title) 
       self_title.text = "enter the title" 
    end

}


local slideshowexport_label_subtitle= dt.new_widget("label")
{
     label = _('slideshow subtitle:'),
     ellipsize = "start",
     halign = "start"
}


slideshowexport_entry_subtitle = dt.new_widget("entry")
{
    text = "", 
    sensitive = true,
    is_password = true,
    editable = true,
    tooltip = _('enter your slideshow subtitle'),
    reset_callback = function(self_subtitle) 
       self_subtitle.text = "" 
    end

}


slideshowexport_combobox_font_size_title = dt.new_widget("combobox")
{
    label = _('title font size'), 
    tooltip =_('sets the font size of the title'),
    value = dt.preferences.read("slideshowexport", "selected_font_size_title", "integer"), --0
    changed_callback = function(sel_font_size_title) 
    dt.preferences.write("slideshowexport", "selected_font_size_title", "integer", sel_font_size_title.selected)
    end,
    "20", "30","40","50","60","70","80","90","100",
    reset_callback = function(self_font_size_title)
       self_font_size_title.value = 5
    end
}     


slideshowexport_combobox_title_time = dt.new_widget("combobox")
{
    label = _('title sequence time'), 
    tooltip =_('sets the display duration of the title'),
    value = dt.preferences.read("slideshowexport", "selected_title_time", "integer"), --0
    changed_callback = function(sel_title_time) 
    dt.preferences.write("slideshowexport", "selected_title_time", "integer", sel_title_time.selected)
    end,
    "1 s", "2 s","3 s","4 s","5 s","6 s","7 s","8 s","9 s","10 s","11 s","12 s","13 s","14 s","15 s","16 s","17 s","18 s","19 s","20 s","21 s","22 s","23 s","24 s","25 s","26 s","27 s","28 s","29 s","30 s",
    reset_callback = function(self_title_time)
       self_title_time.value = 10
    end
}   

local slideshowexport_label_slideshow_options= dt.new_widget("label")
{
     label = _('slideshow options'),
     ellipsize = "start",
     halign = "end"
}

local slideshowexport_label_line2= dt.new_widget("label")
{
     label = "_______________________________________________",
     ellipsize = "start",
     halign = "end"
}

slideshowexport_combobox_display_time = dt.new_widget("combobox")
{
    label = _('image display time'), 
    tooltip =_('sets the display duration of the image'),
    value = dt.preferences.read("slideshowexport", "selected_display_time", "integer"), --0
    changed_callback = function(sel_display_time) 
    dt.preferences.write("slideshowexport", "selected_display_time", "integer", sel_display_time.selected)
    end,
    "1 s", "2 s","3 s","4 s","5 s","6 s","7 s","8 s","9 s","10 s","11 s","12 s","13 s","14 s","15 s","16 s","17 s","18 s","19 s","20 s","21 s","22 s","23 s","24 s","25 s","26 s","27 s","28 s","29 s","30 s",
    reset_callback = function(self_display_time)
       self_display_time.value = 15
    end
}   

slideshowexport_combobox_blending_time = dt.new_widget("combobox")
{
    label = _('crossfade time'), 
    tooltip =_('sets the crossfade duration of the image'),
    value = dt.preferences.read("slideshowexport", "selected_blending_time", "integer"), --0
    changed_callback = function(sel_blending_time) 
    dt.preferences.write("slideshowexport", "selected_blending_time", "integer", sel_blending_time.selected)
    end,
    "1 s", "2 s","3 s","4 s","5 s","6 s","7 s","8 s","9 s","10 s",
    reset_callback = function(self_blending_time)
       self_blending_time.value = 3
    end
}  


local slideshowexport_label_closing_credit_options= dt.new_widget("label")
{
     label = _('closing credit options'),
     ellipsize = "start",
     halign = "end"
}

local slideshowexport_label_line3= dt.new_widget("label")
{
     label = "_______________________________________________",
     ellipsize = "start",
     halign = "end"
}

local slideshowexport_label_copyright= dt.new_widget("label")
{
     label = _('copyright:'),
     ellipsize = "start",
     halign = "start"
}


slideshowexport_entry_copyright = dt.new_widget("entry")
{
    text = _('©YYYY - Author'), 
    sensitive = true,
    is_password = true,
    editable = true,
    tooltip = _('enter you the copyright information in the following form (YYYY - Author)'),
    reset_callback = function(self_copyright) 
       self_copyright.text = "YYYY - Author" 
    end

}

slideshowexport_combobox_font_size_copyright = dt.new_widget("combobox")
{
    label = _('copyright font size'), 
    tooltip =_('sets the font size of the copyright'),
    value = dt.preferences.read("slideshowexport", "selected_font_size_copyright", "integer"), --0
    changed_callback = function(sel_font_size_copyright) 
    dt.preferences.write("slideshowexport", "selected_font_size_copyright", "integer", sel_font_size_copyright.selected)
    end,
    "20", "30","40","50","60","70","80","90","100",
    reset_callback = function(self_font_size_copyright)
       self_font_size_copyright.value = 5
    end
} 



local slideshowexport_label_video_options= dt.new_widget("label")
{
     label = _('video options'),
     ellipsize = "start",
     halign = "end"
}

local slideshowexport_label_line4= dt.new_widget("label")
{
     label = "_______________________________________________",
     ellipsize = "start",
     halign = "end"
}

slideshowexport_combobox_video_bitrate = dt.new_widget("combobox")
{
    label = _('bit rate'), 
    tooltip =_('sets the video quality\nhigh quality = 20000k\nlow quality = 5000k\ndefault quality = 10000k'),
    sensitive = dt.preferences.read("slideshowexport", "senititive_video_bitrate", "bool"),
    value = dt.preferences.read("slideshowexport", "selected_video_bitrate", "integer"), --0
    changed_callback = function(sel_video_bitrate) 
    dt.preferences.write("slideshowexport", "selected_video_bitrate", "integer", sel_video_bitrate.selected)
    end,
    "5000k", "6000k","7000k","8000k","10000k","12000k","14000k","16000k","18000k","20000k",
    reset_callback = function(self_video_bitrate)
       self_video_bitrate.value = 5
    end
}     


slideshowexport_combobox_video_quality = dt.new_widget("combobox")
{
    label = _('video quality'), 
    tooltip =_('sets the video quality\nhigh quality = 1\nlow quality = 31\ndefault quality = 5'),
    sensitive =dt.preferences.read("slideshowexport", "sensitive_video_quality", "bool"),
    value = dt.preferences.read("slideshowexport", "selected_video_quality", "integer"), --0
    changed_callback = function(sel_video_quality) 
    dt.preferences.write("slideshowexport", "selected_video_quality", "integer", sel_video_quality.selected)
    end,
    "1", "2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24","25","26","27","28","29","30","31",
    reset_callback = function(self_quality_framerate)
       self_quality_framerate.value = 5
    end
}     

slideshowexport_combobox_video_format = dt.new_widget("combobox")
{
    label = _('format'), 
    tooltip =_('sets the video container / video codec'),
    value = dt.preferences.read("slideshowexport", "selected_video_format", "integer"), --0
    changed_callback = function(sel_video_format) 
    dt.preferences.write("slideshowexport", "selected_video_format", "integer", sel_video_format.selected)
      if (sel_video_format.selected == 1) then
          slideshowexport_combobox_video_bitrate.sensitive=false    
          slideshowexport_combobox_video_quality.sensitive=true
          dt.preferences.write("slideshowexport", "sensitive_video_bitrate", "bool", false)
          dt.preferences.write("slideshowexport", "sensitive_video_quality", "bool", true)
      elseif (sel_video_format.selected == 2) then  
          slideshowexport_combobox_video_bitrate.sensitive=true    
          slideshowexport_combobox_video_quality.sensitive=false
          dt.preferences.write("slideshowexport", "sensitive_video_bitrate", "bool", true)
          dt.preferences.write("slideshowexport", "sensitive_video_quality", "bool", false)
      elseif (sel_video_format.selected == 3) then  
          slideshowexport_combobox_video_bitrate.sensitive=true    
          slideshowexport_combobox_video_quality.sensitive=false
          dt.preferences.write("slideshowexport", "sensitive_video_bitrate", "bool", true)
          dt.preferences.write("slideshowexport", "sensitive_video_quality", "bool", false) 
      elseif (sel_video_format.selected == 3) then  
          slideshowexport_combobox_video_bitrate.sensitive=true    
          slideshowexport_combobox_video_quality.sensitive=false
          dt.preferences.write("slideshowexport", "sensitive_video_bitrate", "bool", true)
          dt.preferences.write("slideshowexport", "sensitive_video_quality", "bool", false)   
      end
        
    end,
    "MPEG 4 / MPEG4 Part 2","MPEG 4 / H.264 AVC","MPEG / MPEG 2","MPEG 4 / HEVC",
    reset_callback = function(self_video_format)
       self_video_format.value = 1

    end
}     
    
slideshowexport_combobox_video_resolution = dt.new_widget("combobox")
{
    label = _('resolution'), 
    tooltip =_('sets the video resolution'),
    value = dt.preferences.read("slideshowexport", "selected_video_resolution", "integer"), --0
    changed_callback = function(sel_video_resolution) 
    dt.preferences.write("slideshowexport", "selected_video_resolution", "integer", sel_video_resolution.selected)
    end,
    "HDTV 720p - 1280x720","HDTV 1080p - 1920x1080","UHD TV - 3840×2160",
    reset_callback = function(self_video_resolution)
       self_video_resolution.value = 2
    end
}     

slideshowexport_combobox_video_framerate = dt.new_widget("combobox")
{
    label = _('frame rate'), 
    tooltip =_('sets the video frame rate'),
    value = dt.preferences.read("slideshowexport", "selected_video_framerate", "integer"), --0
    changed_callback = function(sel_video_framerate) 
    dt.preferences.write("slideshowexport", "selected_video_framerate", "integer", sel_video_framerate.selected)
    end,
    "24 f/s", "25 f/s","30 f/s","50 f/s","60 f/s",
    reset_callback = function(self_video_framerate)
       self_video_framerate.value = 2
    end
}     


local slideshowexport_label_slideshowexport_target_storage= dt.new_widget("label")
{
     label = _('target video'),
     ellipsize = "start",
     halign = "end"
}

local slideshowexport_label_line5= dt.new_widget("label")
{
     label = "_______________________________________________",
     ellipsize = "start",
     halign = "end"
}


slideshowexport_file_chooser_button_target_directory = dt.new_widget("file_chooser_button")
{
    title = _('select target directory'),  -- The title of the window when choosing a file
    is_directory = true,             -- True if the file chooser button only allows directories to be selecte
    tooltip =_('select the target storage for the output video.')
}


local slideshowexport_label_target_filename= dt.new_widget("label")
{
     label = _('filename without suffix'),
     ellipsize = "start",
     halign = "start"
}


local slideshowexport_entry_video_filename = dt.new_widget("entry")
{
    text = "", 
    is_password = true,
    editable = true,
    tooltip = _('enter the target video filename without suffix'),
    reset_callback = function(self_slideshowexport) 
       self_slideshowexport.text = "" 
    end

}

local slideshowexport_label_video_info= dt.new_widget("label")
{
     label = _('video information'),
     ellipsize = "start",
     halign = "end"
}

local slideshowexport_label_line6= dt.new_widget("label")
{
     label = "_______________________________________________",
     ellipsize = "start",
     halign = "end"
}

slideshowexport_label_image_count = dt.new_widget("label")
{
     label = _('selected images:\t\t\t\t') ..slideshowexport_number_of_images,
     ellipsize = "start",
     halign = "start"
}

slideshowexport_label_play_time = dt.new_widget("label")
{
     label = _('calculated play time:\t\t\t\t') ..slideshowexport_play_time,
     ellipsize = "start",
     halign = "start"
}


slideshowexport_button_calculate_playtime = dt.new_widget("button")
{
      label = _('calculate playtime'),
      tooltip =_('calculate the slideshow playtime'),
      clicked_callback = function(calculate_playtime) 
          cout_selected_images=0
          local slideshowexport_selection = dt.gui.selection()
          for _,img in pairs(slideshowexport_selection) do
             cout_selected_images=cout_selected_images+1
          end
          slideshowexport_label_image_count.label=_('selected images:\t\t\t\t')..cout_selected_images

            if (slideshowexport_check_button_black_frame.value) then
                slideshowexport_play_time=slideshowexport_extra_long_blackframe + slideshowexport_blackframe + dt.preferences.read("slideshowexport", "selected_title_time", "integer") + slideshowexport_blackframe + (dt.preferences.read("slideshowexport", "selected_display_time", "integer")*cout_selected_images) + slideshowexport_blackframe + dt.preferences.read("slideshowexport", "selected_title_time", "integer") + slideshowexport_blackframe - (dt.preferences.read("slideshowexport", "selected_blending_time", "integer")*cout_selected_images) - (dt.preferences.read("slideshowexport", "selected_blending_time", "integer")*2)
                
                play_hour = math.floor(slideshowexport_play_time / 60 / 60)
                play_minute = math.floor((slideshowexport_play_time / 60 / 60 - play_hour) * 60)
                play_second = math.floor((((slideshowexport_play_time / 60 /60 - play_hour) *60) - play_minute) *60)
                slideshowexport_label_play_time.label = _('calculated play time:\t\t\t\t') ..string.format("%02d",play_hour)..":"..string.format("%02d",play_minute)..":"..string.format("%02d",play_second)
            else    
                slideshowexport_play_time=slideshowexport_blackframe + dt.preferences.read("slideshowexport", "selected_title_time", "integer") + slideshowexport_blackframe + (dt.preferences.read("slideshowexport", "selected_display_time", "integer")*cout_selected_images) + slideshowexport_blackframe + dt.preferences.read("slideshowexport", "selected_title_time", "integer") + slideshowexport_blackframe - (dt.preferences.read("slideshowexport", "selected_blending_time", "integer")*cout_selected_images) - (dt.preferences.read("slideshowexport", "selected_blending_time", "integer")*2)
                
                play_hour = math.floor(slideshowexport_play_time / 60 / 60)
                play_minute = math.floor((slideshowexport_play_time / 60 / 60 - play_hour) * 60)
                play_second = math.floor((((slideshowexport_play_time / 60 /60 - play_hour)*60) - play_minute) *60)
                slideshowexport_label_play_time.label = _('calculated play time:\t\t\t\t') ..string.format("%02d",play_hour)..":"..string.format("%02d",play_minute)..":"..string.format("%02d",play_second)
            end
            
      end
}

-- GUI CALL
  
local export_widget = dt.new_widget("box") {
    orientation = "vertical",
    slideshowexport_label_title_sequence_options,
    slideshowexport_label_line1,
    slideshowexport_check_button_black_frame,
    slideshowexport_label_title,
    slideshowexport_entry_title,
    slideshowexport_label_subtitle,
    slideshowexport_entry_subtitle,
    slideshowexport_combobox_font_size_title,
    slideshowexport_combobox_title_time,
    slideshowexport_label_slideshow_options,
    slideshowexport_label_line2,
    slideshowexport_combobox_display_time,
    slideshowexport_combobox_blending_time,
    slideshowexport_label_closing_credit_options,
    slideshowexport_label_line3,
    slideshowexport_label_copyright,
    slideshowexport_entry_copyright,
    slideshowexport_combobox_font_size_copyright,
    slideshowexport_label_video_options,
    slideshowexport_label_line4,
    slideshowexport_combobox_video_format,
    slideshowexport_combobox_video_resolution,
    slideshowexport_combobox_video_framerate,
    slideshowexport_combobox_video_bitrate,
    slideshowexport_combobox_video_quality,
    slideshowexport_label_slideshowexport_target_storage,
    slideshowexport_label_line5,
    slideshowexport_file_chooser_button_target_directory,
    slideshowexport_label_target_filename,
    slideshowexport_entry_video_filename,
    slideshowexport_label_video_info,
    slideshowexport_label_line6,
    slideshowexport_label_image_count,
    slideshowexport_label_play_time,
    slideshowexport_button_calculate_playtime,
}



-- EXPORT INFO
local function show_status(storage, image, format, filename,
  number, total, high_quality, extra_data)
      dt.print(_('export PNG images for slideshow video ')..tostring(truncate(number)).." / "..tostring(truncate(total)))  
      dt.print_error("export "..number.."/"..total.." PNG images to "..slideshowexport_darktable_tmpdir)
      slideshowexport_number_of_images=total
end


-- MAIN PROGRAM
local function create_slideshow_image(storage, image_table, extra_data) --finalize
job = dt.gui.create_job(_('creating slideshow video'), true, stop_selection)

job.percent = 0.1
-- CHECK INSTALLED SOFTWARE
dt.print_error("check installed software...")
  if (not (checkIfBinExists("convert"))) then
     dt.print(_('ERROR: convert not found. please install imagemagick.'))
     dt.print_error(_('convert not found. please install imagemagick.'))
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return
  elseif  (not (checkIfBinExists("identify"))) then
     dt.print(_('ERROR: identify not found. please install imagemagick.'))
     dt.print_error(_('identify not found. please install imagemagick.'))
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return
  elseif  (not (checkIfBinExists("date"))) then
     dt.print(_('ERROR: date not found. please install the core utilities.'))
     dt.print_error(_('date not found. please install core utilities.'))
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return
  elseif  (not (checkIfBinExists("cut"))) then
     dt.print(_('ERROR: cut not found. please install the core utilities.'))
     dt.print_error(_('cut not found. please install core utilities.'))
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return
  elseif  (not (checkIfBinExists("tr"))) then
     dt.print(_('ERROR: tr not found. please install the core utilities.'))
     dt.print_error(_('tr not found. please install core utilities.'))
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return
  elseif  (not (checkIfBinExists("mv"))) then
     dt.print(_('ERROR: mv not found. please install the core utilities.'))
     dt.print_error(_('mv not found. please install core utilities.'))
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return
  elseif  (not (checkIfBinExists("rm"))) then
     dt.print(_('ERROR: rm not found. please install the core utilities.'))
     dt.print_error(_('rm not found. please install core utilities.'))
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return
  elseif  (not (checkIfBinExists("melt"))) then
     dt.print(_('ERROR: melt not found. please install melt and mlt with ffmpeg or libav support.'))
     dt.print_error(_('melt not found. please install melt and mlt with ffmpeg or libav support.'))
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return
  elseif (dt.control.execute("melt -query \"video_codecs\" | grep libx264") ~= 0) then 
     dt.print(_('ERROR: libx264 not found. please install libx264.'))
     dt.print_error("ERROR: libx264 not found. please install libx264")
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return 
  elseif (dt.control.execute("melt -query \"video_codecs\" | grep libx265") ~= 0) then 
     dt.print(_('ERROR: libx265 not found. please install libx265.'))
     dt.print_error("ERROR: libx265 not found. please install libx265")
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return   
   elseif (dt.control.execute("melt -query \"video_codecs\" | grep mpeg2video") ~= 0) then 
     dt.print(_('ERROR: mpeg2 support not found. please install ffmpeg with mpeg2 support.'))
     dt.print_error("ERROR: mpeg2 support not found. please install ffmpeg with mpeg2 support.")
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return     
    elseif (dt.control.execute("melt -query \"video_codecs\" | grep mpeg4") ~= 0) then 
     dt.print(_('ERROR: mpeg4 part2 support not found. please install ffmpeg with mpeg4 support.'))
     dt.print_error("ERROR: mpeg part 2 support not found. please install ffmpeg with mpeg4 support.")
     dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
     return   
  end 


 
 -- CHECK CODEC
    if (dt.control.execute("melt -query \"video_codecs\" | grep libx265") ~= 0) then
       dt.print_error("x265")
       return       
    end
dt.print(_('sort and rename the images...'))  
-- CREATE IMAGE PATH AND EXIV INFOS FOR SORTING
slideshowexport_number_of_images=0

image_table_with_unix_time_key={}

        for _,v in pairs(image_table) do
            slideshowexport_number_of_images=slideshowexport_number_of_images+1  
           --read create date from exiv tag
           local cmd_exiv_date="identify -format \"%[exif:DateTimeOriginal*]\" "..v.." | cut -d= -f2 | cut -d \" \" -f1 | tr : -"           
           local handle = io.popen(cmd_exiv_date)
           local create_date_string = handle:read("*a")
           handle:close()

           -- read create time from exiv tag
           local cmd_exiv_time="identify -format \"%[exif:DateTimeOriginal*]\" "..v.." | cut -d= -f2 | cut -d \" \" -f2"
           local handle = io.popen(cmd_exiv_time)
           local create_time_string = handle:read("*a")
           handle:close()

           -- convert to unix time for table key
           local cmd_unix_time="date -d '"..create_date_string.." "..create_time_string.."' +%s"
           local handle = io.popen(cmd_unix_time)
           local create_unix_time_string = handle:read("*a")  
           handle:close()
           local image_unixtime = tonumber(create_unix_time_string)
           
           image_table_with_unix_time_key[slideshowexport_number_of_images]={path = v, date=image_unixtime}
                            
        end

-- CHECK SELECTED IMAGES  (don't move forward, slideshowexport_number_of_images)
  if (slideshowexport_number_of_images<1) then
     dt.print(_('ERROR: not enough pictures selected. please select one or more images\nfor the slideshow.'))
      return
  elseif (slideshowexport_number_of_images>=51) then  
     dt.print(_('you have selected more then 50 images. the slideshow process could take a very long time! \nhave a nice beake.'))
  end           
        
        
--SORT TABLE AND MOVE IMAGES TO LOCAL tmp DIRECTORY
local function sortByDateLowest(a, b)
     return a.date < b.date
end 
table.sort(image_table_with_unix_time_key, sortByDateLowest)
slideshowexport_image_index=4

for i = 1, #image_table_with_unix_time_key do

    mv_result=dt.control.execute("mv \""..image_table_with_unix_time_key[i].path.."\" \""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_image_index)..".png\"")
    if (mv_result == 0) then
       dt.print_error("mv \""..image_table_with_unix_time_key[i].path.."\" \""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_image_index)..".png\"")
    else  
       dt.print("ERROR: Can't move exported images to "..slideshowexport_local_tmp_path)
       dt.print_error("ERROR: Can't move exported images to "..slideshowexport_local_tmp_path)
       for _,v in pairs(image_table) do
         dt.control.execute("rm \""..v.."\"")
       return
       end
    end
   slideshowexport_image_index=slideshowexport_image_index+1
end


job.percent = 0.2



-- CHECK GUI INPUT (TITLE, COPYRIGHT, MOVIE PATH AND MOVIE FILENAME)
slideshowexport_cmd_title = slideshowexport_entry_title.text
    if (slideshowexport_cmd_title == "") then
       dt.print(_('ERROR: no title found. please enter the title.'))  
       dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
       return
    end
    slideshowexport_cmd_copyright = slideshowexport_entry_copyright.text
    if (slideshowexport_cmd_copyright == "") then
       dt.print(_('ERROR: no copyright found. please enter the copyright information.'))  
       dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
       return
    end
    slideshowexport_cmd_output_path = slideshowexport_file_chooser_button_target_directory.value
    if (slideshowexport_cmd_output_path == nil) then
       dt.print(_('ERROR: no target directory found. please select the target directory.'))  
       dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
       return
    end   
    slideshowexport_cmd_video_filename = slideshowexport_entry_video_filename.text
    if (slideshowexport_cmd_video_filename == "") then
       dt.print(_('ERROR: no filename found. please enter the video filename without suffix.'))  
       dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")
       return
    end     

job.percent = 0.3




-- CREATE BLACKFRAME IMAGE
slideshowexport_image_size=0
  if (slideshowexport_combobox_video_resolution.value == "HDTV 720p - 1280x720") then
    slideshowexport_image_width="1280"
    slideshowexport_image_hight="720"
  elseif  (slideshowexport_combobox_video_resolution.value == "HDTV 1080p - 1920x1080") then
    slideshowexport_image_width="1920"
    slideshowexport_image_hight="1080"
  elseif (slideshowexport_combobox_video_resolution.value == "UHD TV - 3840×2160") then
    slideshowexport_image_width="3840"
    slideshowexport_image_hight="2160"
  else
    dt.print_error("Unknown video size")
    return
  end
dt.control.execute("convert -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." xc:black \""..slideshowexport_local_tmp_path.."/slideshow_img00001.png\"")
dt.print_error("convert -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." xc:black \""..slideshowexport_local_tmp_path.."/slideshow_img00001.png\"")
  
dt.control.execute("convert -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." xc:black \""..slideshowexport_local_tmp_path.."/slideshow_img00003.png\"")
dt.print_error("convert -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." xc:black \""..slideshowexport_local_tmp_path.."/slideshow_img00003.png\"")  
  
slideshowexport_blackframe_number_closing1=4+slideshowexport_number_of_images
slideshowexport_blackframe_number_closing2=6+slideshowexport_number_of_images
dt.control.execute("convert -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." xc:black \""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_blackframe_number_closing1)..".png\"")  
dt.print_error("convert -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." xc:black \""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_blackframe_number_closing1)..".png\"")
dt.control.execute("convert -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." xc:black \""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_blackframe_number_closing2)..".png\"")  
dt.print_error("convert -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." xc:black \""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_blackframe_number_closing2)..".png\"")

-- CREATE TITLE IMAGE
slideshowexport_font_size_title=slideshowexport_combobox_font_size_title.value
slideshowexport_cmd_subtitle=slideshowexport_entry_subtitle.text
if (slideshowexport_cmd_subtitle ~= "") then
   slideshowexport_cmd_title=slideshowexport_cmd_title.."\n"..slideshowexport_cmd_subtitle
end

dt.control.execute("convert -background black -fill white -font Helvetica-Bold -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." -pointsize "..slideshowexport_font_size_title.." -gravity center label:'"..slideshowexport_cmd_title.."' \""..slideshowexport_local_tmp_path.."/slideshow_img00002.png\"") 
dt.print_error("convert -background black -fill white -font Helvetica-Bold -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." -pointsize "..slideshowexport_font_size_title.." -gravity center label:'"..slideshowexport_cmd_title.."' \""..slideshowexport_local_tmp_path.."/slideshow_img00002.png\"")

-- CREATE COPYRIGHT IMAGE
slideshowexport_font_size_copyright=slideshowexport_combobox_font_size_copyright.value
slideshowexport_cmd_copyright=slideshowexport_entry_copyright.text
slideshowexport_blackframe_number_copyright=5+slideshowexport_number_of_images


dt.control.execute("convert -background black -fill white -font Helvetica-Bold -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." -pointsize "..slideshowexport_font_size_copyright.." -gravity center label:'"..slideshowexport_cmd_copyright.."' \""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_blackframe_number_copyright)..".png\"") 

dt.print_error("convert -background black -fill white -font Helvetica-Bold -size "..slideshowexport_image_width.."x"..slideshowexport_image_hight.." -pointsize "..slideshowexport_font_size_copyright.." -gravity center label:'"..slideshowexport_cmd_copyright.."' \""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_blackframe_number_copyright)..".png\"") 

job.percent = 0.4


-- CREATE MPEG MOVIE
if ((slideshowexport_combobox_video_resolution.value == "HDTV 720p - 1280x720") and (slideshowexport_combobox_video_framerate.value == "24 f/s")) then
slideshowexport_profile="atsc_720p_24"
slideshowexport_framerates=24

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 720p - 1280x720") and (slideshowexport_combobox_video_framerate.value == "25 f/s")) then
slideshowexport_profile="atsc_720p_25"
slideshowexport_framerates=25

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 720p - 1280x720") and (slideshowexport_combobox_video_framerate.value == "30 f/s")) then
slideshowexport_profile="atsc_720p_30"
slideshowexport_framerates=30

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 720p - 1280x720") and (slideshowexport_combobox_video_framerate.value == "50 f/s")) then
slideshowexport_profile="atsc_720p_50"
slideshowexport_framerates=50

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 720p - 1280x720") and (slideshowexport_combobox_video_framerate.value == "60 f/s")) then
slideshowexport_profile="atsc_720p_60"
slideshowexport_framerates=60

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 1080p - 1920x1080") and (slideshowexport_combobox_video_framerate.value == "24 f/s")) then
slideshowexport_profile="atsc_1080p_24"
slideshowexport_framerates=24

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 1080p - 1920x1080") and (slideshowexport_combobox_video_framerate.value == "25 f/s")) then
slideshowexport_profile="atsc_1080p_25"
slideshowexport_framerates=25

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 1080p - 1920x1080") and (slideshowexport_combobox_video_framerate.value == "30 f/s")) then
slideshowexport_profile="atsc_1080p_30"
slideshowexport_framerates=30

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 1080p - 1920x1080") and (slideshowexport_combobox_video_framerate.value == "50 f/s")) then
slideshowexport_profile="atsc_1080p_50"
slideshowexport_framerates=50

elseif ((slideshowexport_combobox_video_resolution.value == "HDTV 1080p - 1920x1080") and (slideshowexport_combobox_video_framerate.value == "60 f/s")) then
slideshowexport_profile="atsc_1080p_60"
slideshowexport_framerates=60

elseif ((slideshowexport_combobox_video_resolution.value == "UHD TV - 3840×2160") and (slideshowexport_combobox_video_framerate.value == "24 f/s")) then
slideshowexport_profile="uhd_2160p_24"
slideshowexport_framerates=24

elseif ((slideshowexport_combobox_video_resolution.value == "UHD TV - 3840×2160") and (slideshowexport_combobox_video_framerate.value == "25 f/s")) then
slideshowexport_profile="uhd_2160p_25"
slideshowexport_framerates=25

elseif ((slideshowexport_combobox_video_resolution.value == "UHD TV - 3840×2160") and (slideshowexport_combobox_video_framerate.value == "30 f/s")) then
slideshowexport_profile="uhd_2160p_30"
slideshowexport_framerates=30

elseif ((slideshowexport_combobox_video_resolution.value == "UHD TV - 3840×2160") and (slideshowexport_combobox_video_framerate.value == "50 f/s")) then
slideshowexport_profile="uhd_2160p_50"
slideshowexport_framerates=50

elseif ((slideshowexport_combobox_video_resolution.value == "UHD TV - 3840×2160") and (slideshowexport_combobox_video_framerate.value == "60 f/s")) then
slideshowexport_profile="uhd_2160p_60"
slideshowexport_framerates=60

else
 dt.print("ERROR: Unknown profile")
 dt.print_error("ERROR: Unknown profile")

end

if (slideshowexport_combobox_video_format.value == "MPEG 4 / MPEG4 Part 2") then
slideshowexport_codec="mpeg4"
slideshowexport_filename_suffix=".mp4"

elseif (slideshowexport_combobox_video_format.value == "MPEG 4 / H.264 AVC") then
slideshowexport_codec="libx264"
slideshowexport_filename_suffix=".mp4"

elseif (slideshowexport_combobox_video_format.value == "MPEG / MPEG 2") then
slideshowexport_codec="mpeg2video"
slideshowexport_filename_suffix=".mpg"

elseif (slideshowexport_combobox_video_format.value == "MPEG 4 / HEVC") then
slideshowexport_codec="libx265"
slideshowexport_filename_suffix=".mp4"

else
dt.print("ERROR: Unknown codec or container")
dt.print_error("ERROR: Unknown codec or container")

end

if (slideshowexport_combobox_title_time.value == "1 s") then
slideshowexport_title_frames=1*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "2 s") then
slideshowexport_title_frames=2*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "3 s") then
slideshowexport_title_frames=3*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "4 s") then
slideshowexport_title_frames=4*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "5 s") then
slideshowexport_title_frames=5*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "6 s") then
slideshowexport_title_frames=6*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "7 s") then
slideshowexport_title_frames=7*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "8 s") then
slideshowexport_title_frames=8*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "9 s") then
slideshowexport_title_frames=9*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "10 s") then
slideshowexport_title_frames=10*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "11 s") then
slideshowexport_title_frames=12*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "13 s") then
slideshowexport_title_frames=13*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "14 s") then
slideshowexport_title_frames=14*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "15 s") then
slideshowexport_title_frames = 15*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "16 s") then
slideshowexport_title_frames=16*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "17 s") then
slideshowexport_title_frames=17*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "18 s") then
slideshowexport_title_frames=18*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "19 s") then
slideshowexport_title_frames=19*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "20 s") then
slideshowexport_title_frames=20*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "21 s") then
slideshowexport_title_frames=21*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "22 s") then
slideshowexport_title_frames=22*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "23 s") then
slideshowexport_title_frames=23*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "24 s") then
slideshowexport_title_frames=24*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "25 s") then
slideshowexport_title_frames=25*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "26 s") then
slideshowexport_title_frames=26*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "27 s") then
slideshowexport_title_frames=27*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "28 s") then
slideshowexport_title_frames=28*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "29 s") then
slideshowexport_title_frames=29*slideshowexport_framerates
elseif
(slideshowexport_combobox_title_time.value == "30 s") then
slideshowexport_title_frames=30*slideshowexport_framerates
else
dt.print_error("No title time found")
end

slideshowexport_black1_frames=slideshowexport_blackframe*slideshowexport_framerates
slideshowexport_black2_frames=slideshowexport_blackframe*slideshowexport_framerates
slideshowexport_long_blfr=0

if (slideshowexport_check_button_black_frame.value) then
slideshowexport_long_blfr=slideshowexport_extra_long_blackframe*slideshowexport_framerates
slideshowexport_black1_frames=slideshowexport_black1_frames+slideshowexport_long_blfr
end

if (slideshowexport_combobox_display_time.value == "1 s") then
slideshowexport_image_frames=1*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "2 s") then
slideshowexport_image_frames=2*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "3 s") then
slideshowexport_image_frames=3*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "4 s") then
slideshowexport_image_frames=4*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "5 s") then
slideshowexport_image_frames=5*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "6 s") then
slideshowexport_image_frames=6*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "7 s") then
slideshowexport_image_frames=7*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "8 s") then
slideshowexport_image_frames=8*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "9 s") then
slideshowexport_image_frames=9*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "10 s") then
slideshowexport_image_frames=10*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "11 s") then
slideshowexport_image_frames=11*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "12 s") then
slideshowexport_image_frames=12*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "13 s") then
slideshowexport_image_frames=13*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "14 s") then
slideshowexport_image_frames=14*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "15 s") then
slideshowexport_image_frames=15*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "16 s") then
slideshowexport_image_frames=16*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "17 s") then
slideshowexport_image_frames=17*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "18 s") then
slideshowexport_image_frames=18*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "19 s") then
slideshowexport_image_frames=19*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "20 s") then
slideshowexport_image_frames=20*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "21 s") then
slideshowexport_image_frames=21*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "22 s") then
slideshowexport_image_frames=22*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "23 s") then
slideshowexport_image_frames=23*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "24 s") then
slideshowexport_image_frames=24*slideshowexport_framerates   
elseif (slideshowexport_combobox_display_time.value == "25 s") then
slideshowexport_image_frames=25*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "26 s") then
slideshowexport_image_frames=26*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "27 s") then
slideshowexport_image_frames=27*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "28 s") then
slideshowexport_image_frames=28*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "29 s") then
slideshowexport_image_frames=29*slideshowexport_framerates
elseif (slideshowexport_combobox_display_time.value == "30 s") then
slideshowexport_image_frames=30*slideshowexport_framerates 
end



if (slideshowexport_combobox_blending_time.value == "1 s") then
slideshowexport_cross_frames=1*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "2 s") then
slideshowexport_cross_frames=2*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "3 s") then
slideshowexport_cross_frames=3*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "4 s") then
slideshowexport_cross_frames=4*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "5 s") then
slideshowexport_cross_frames=5*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "6 s") then
slideshowexport_cross_frames=6*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "7 s") then
slideshowexport_cross_frames=7*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "8 s") then
slideshowexport_cross_frames=8*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "9 s") then
slideshowexport_cross_frames=9*slideshowexport_framerates 
elseif (slideshowexport_combobox_blending_time.value == "10 s") then
slideshowexport_cross_frames=10*slideshowexport_framerates 
end


slideshowexport_copyright_frames=slideshowexport_title_frames
slideshowexport_vb_quality=slideshowexport_combobox_video_bitrate.value
slideshowexport_qscale_quality=slideshowexport_combobox_video_quality.value
slideshowexport_cmd_output_filename=slideshowexport_cmd_video_filename..slideshowexport_filename_suffix



job.percent = 0.5

--CREATE FRAME PARAMETERS
local slideshowexport_black_frame1_parameters="\""..slideshowexport_local_tmp_path.."/slideshow_img00001.png\" out="..slideshowexport_black1_frames.." -mix "..slideshowexport_cross_frames.." -mixer luma "

local slideshowexport_title_parameters="\""..slideshowexport_local_tmp_path.."/slideshow_img00002.png\" out="..slideshowexport_title_frames.." -mix "..slideshowexport_cross_frames.." -mixer luma "

local slideshowexport_black_frame2_parameters="\""..slideshowexport_local_tmp_path.."/slideshow_img00003.png\" out="..slideshowexport_black2_frames.." -mix "..slideshowexport_cross_frames.." -mixer luma "


slideshowexport_image_parameters=""
for i=4, slideshowexport_number_of_images+3 do
img_parameters="\""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",i)..".png\" out="..slideshowexport_image_frames.." -mix "..slideshowexport_cross_frames.." -mixer luma " 
slideshowexport_image_parameters=slideshowexport_image_parameters..img_parameters  
end

local slideshowexport_black_frame3_parameters="\""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_number_of_images+4)..".png\" out="..slideshowexport_black2_frames.." -mix "..slideshowexport_cross_frames.." -mixer luma "


local slideshowexport_copyright_parameters="\""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_number_of_images+5)..".png\" out="..slideshowexport_copyright_frames.." -mix "..slideshowexport_cross_frames.." -mixer luma "

local slideshowexport_black_frame4_parameters="\""..slideshowexport_local_tmp_path.."/slideshow_img"..string.format("%05d",slideshowexport_number_of_images+6)..".png\" out="..slideshowexport_black2_frames.." -mix "..slideshowexport_cross_frames.." -mixer luma "

job.percent = 0.6


-- MOVIE EXPORT COMMAND
if (slideshowexport_combobox_video_format.value == "MPEG 4 / MPEG4 Part 2") then --qscale
   
    dt.print(_('creating the video may take longer! please wait...'))
    dt.print_error("melt -verbose -profile "..slideshowexport_profile.." "..slideshowexport_black_frame1_parameters..slideshowexport_title_parameters..slideshowexport_black_frame2_parameters..slideshowexport_image_parameters..slideshowexport_black_frame3_parameters..slideshowexport_copyright_parameters..slideshowexport_black_frame4_parameters.." -consumer avformat:"..slideshowexport_cmd_output_path.."/"..slideshowexport_cmd_video_filename..slideshowexport_filename_suffix.." vcodec="..slideshowexport_codec.." qscale="..slideshowexport_qscale_quality.." an=1")
    
    result_melt=dt.control.execute("melt -verbose -profile "..slideshowexport_profile.." "..slideshowexport_black_frame1_parameters..slideshowexport_title_parameters..slideshowexport_black_frame2_parameters..slideshowexport_image_parameters..slideshowexport_black_frame3_parameters..slideshowexport_copyright_parameters..slideshowexport_black_frame4_parameters.." -consumer avformat:"..slideshowexport_cmd_output_path.."/"..slideshowexport_cmd_video_filename..slideshowexport_filename_suffix.." vcodec="..slideshowexport_codec.." qscale="..slideshowexport_qscale_quality.." an=1")
    if (result_melt == 0) then
       dt.print(_('process successfully completed'))
    else
       dt.print(_('ERROR: melt doesn\'t work. For more information see terminal output'))
    end
    
else  --vb
    dt.print(_('creating the video may take longer! please wait...'))
    dt.print_error("melt -verbose -profile "..slideshowexport_profile.." "..slideshowexport_black_frame1_parameters..slideshowexport_title_parameters..slideshowexport_black_frame2_parameters..slideshowexport_image_parameters..slideshowexport_black_frame3_parameters..slideshowexport_copyright_parameters..slideshowexport_black_frame4_parameters.." -consumer avformat:"..slideshowexport_cmd_output_path.."/"..slideshowexport_cmd_video_filename..slideshowexport_filename_suffix.." vcodec="..slideshowexport_codec.." vb="..slideshowexport_vb_quality.." an=1")    
    
    result_melt=dt.control.execute("melt -verbose -profile "..slideshowexport_profile.." "..slideshowexport_black_frame1_parameters..slideshowexport_title_parameters..slideshowexport_black_frame2_parameters..slideshowexport_image_parameters..slideshowexport_black_frame3_parameters..slideshowexport_copyright_parameters..slideshowexport_black_frame4_parameters.." -consumer avformat:"..slideshowexport_cmd_output_path.."/"..slideshowexport_cmd_video_filename..slideshowexport_filename_suffix.." vcodec="..slideshowexport_codec.." vb="..slideshowexport_vb_quality.." an=1")    
    if (result_melt == 0) then
       dt.print(_('process successfully completed'))
    else
       dt.print(_('ERROR: melt doesn\'t work. For more information see terminal output'))
    end
end
    
    
job.percent = 0.9


-- REMOVE IMAGES FROM LOCAL tmp
result_clean=dt.control.execute("rm \""..slideshowexport_local_tmp_path.."/slideshow_img\"*\".png\"")

-- SLIDESHOW PLAYBACK
play_cmd=""

if (dt.preferences.read("slideshowexport", "autostart_video_play", "bool") == true) then
local slideshow_software_player=dt.preferences.read("slideshowexport", "slideshow_player_command", "string") 
    if (not (checkIfBinExists(slideshow_software_player))) then
        dt.print(_('ERROR: '..slideshow_software_player..' not found. please check the player command.'))
        dt.print_error(_(slideshow_software_player..' not found. please check the player command.'))
        job.valid = false
        return
    else
       play_cmd=slideshow_software_player.." "..slideshowexport_cmd_output_path.."/"..slideshowexport_cmd_video_filename..slideshowexport_filename_suffix
       dt.print_error(play_cmd)
       playerresult=dt.control.execute(play_cmd)
       if (playerresult ~= 0) then
       dt.print(_('ERROR: video playback not possible. please check if the video format is supported.'))
       end
    end

end

job.valid = false
-- END MAIN PROGRAM
end



-- LIMIT EXPORT TP PNG IMAGES
local function support_format(storage, format)
  fmt = string.lower(format.name)
  if string.match(fmt,"png") == nil then
    return false
  else
    return true
  end   
end  



-- REGISTER EXPORT
dt.register_storage("slideshowexport", _('slideshow video'), show_status, create_slideshow_image, support_format, nil, export_widget)

dt.preferences.register("slideshowexport",        -- script: This is a string used to avoid name collision in preferences (i.e namespace). Set it to something unique, usually the name of the script handling the preference.
                        "slideshow_player_command",  -- name
                        "string",                     -- type
                        _('slideshowexport: player command'),            -- label
                        _('set the slideshow player command'),    -- tooltip
                        "melt")                     -- default

dt.preferences.register("slideshowexport",        
                        "autostart_video_play",                                          -- name
                        "bool",                                                   -- type
                        _('slideshowexport: autostart slideshow playback'),                       -- label
                        _('this option enables automatic playback of the finished slideshow video'),                  -- tooltip
                        false)                                                    -- default





