function surf_show(varargin)
% SURF_SHOW Surface display GUI
%
% command-line options:
%  surf_show(command1_name,command1_argument1,...,command1_argumentn,command2_name,command2_argument1,...)
%
%   Valid command names / command arguments:
%     'SURFACE_ADD'             : adds new surface from file
%        filename                   : file name with surface data  
%        [thr,smooth]               : (optional when importing .img/.nii files) threshold value and smoothing level for isosurface computation 
%     'SURFACE_PAINT'           : paints surface
%        filename                   : file name with surface values
%     'SURFACE_PROPERTIES'      : modifies surface properties
%        ['offset',vector]          : surface spatial position offset (three-dimensional vector with values in mm) 
%        ['scale',value]            : surface spatial scaling factor (0-inf)
%        ['color',color]            : surface color (rgb or colormap for painted surfaces) 
%        ['material',name]          : surface material properties
%        ['transparency',value]     : surface transparency (0-1) 
%        ['transparencyrange',value]: surface transparency range (one or two values specifing the range of paint values that are to be rendered transparent) 
%        ['histogramequalization',value] : 0: no effect; 1: non-linear histogram equalization; [a b]: linear histogram rescaling (lower/upper color bounds) 
%        ['showborders',value] :    0: no effect; 1: show only ROI borders (for .annot files) 
%     'LIGHT_ADD'               : adds new light-source
%     'LIGHT_PROPERTIES'        : modifies light-source properties
%        ['color',color]            : light-source color (rgb) 
%        ['position',vector]        : light-source spatial position (three-dimensional vector with values in mm) 
%        ['reference',value]        : light-source position reference frame ('viewer' or 'static') 
%        ['style',value]            : light-source distance ('infinite' or 'local') 
%     'BACKGROUND_PROPERTIES'   : modifies background properties
%        ['color',color]            : background color (rgb) 
%     'VIEW'                    : defines viewpoint
%        viewpoint                  : scalar (1-6 canonical viewpoints) or vector (three-dimensional viewpoint position in mm) 
%     'RESOLUTION'              : defines display surface resolution
%        resolution                 : scalar (1: low-resolution; 2: high-resolution)
%     'PRINT'                   : prints to file
%        ['filename,filename]       : output file name
%        ['view',view]              : 'single' or 'mosaic'
%        ['options',options]        : additional parameters sent to print function (see help print) 
%        ['renderer',renderer]      : 'hardware' or 'software'
%     'CLOSE'                   : closes surf_show window (without warning message)
%        

%% main function

global surf_show_OPENGLWARN; 
OpenGLSoft=isunix&&~ismac;                                      % Set to true to use software OpenGL instead of hardware OpenGL
SPMpath='/speechlab/software/spm8';                             % change to SPM path on your system if necessary 
FSpath=fullfile(fileparts(which(mfilename)),'freesurfer');      % change to freesurfer path on your system if necessary 
save_path=pwd;                                                  % default folder to save/load project files

file_path={fullfile(fileparts(which(mfilename)),'surf')};       % default folder(s) when adding new surfaces/paints
tpath='/speechlab/software/db/ANALYSES';if isdir(tpath), file_path{end+1}=tpath; end
nfile_path=numel(file_path);
file_path{end+1}=pwd;

if OpenGLSoft&&isempty(surf_show_OPENGLWARN), 
    try 
        opengl software;
        if feature('OpenGLLoadStatus')&&~strcmp(questdlg({'To avoid unstabilities run this program from a fresh Matlab session.','Continuing now may cause unstabilities/crashes.','Are you sure you want to continue?'},'warning','Yes','No','No'),'Yes'), return; end
    catch % opengl software now deprecated in unix systems, start matlab with the softwareopengl startup option instead
        try
            opengl HARDWAREBASIC;
        end
    end
end
surf_show_OPENGLWARN=true;
if isempty(which('read_surf'))&&~isempty(dir(fullfile(FSpath,'read_surf.m'))), addpath(FSpath); end
if isempty(which('spm'))&&~isempty(dir(fullfile(SPMpath,'spm.m'))), addpath(SPMpath); end

% initialize variables
REF=[];
SURFACES=[];
LIGHTS=[];
SURFACE_SELECTED=1;
SURFACE_GROUPS=[];
LIGHT_SELECTED=1;
DISPLAYED_SURFACES=[];
surf_show_addlight; 

RESOLUTION=1;
VIEW=load(fullfile(fileparts(mfilename),'surf_show.mat'));
COLOR_BACKGROUND=[1,1,1];
CAMERA_HOLD={};
CLICKTOSELECT=1;
SHOWHEM=3;
DOPRINT='none';
PRINT_OPTIONS={'-djpeg90','-r300','-opengl'};
PRINT_HOLOSELECT=[];
GUI=true;

%initialize figure
hfig=figure('numbertitle','off','menubar','none','toolbar','none','render','opengl','interruptible','off','closeRequestFcn',@surf_show_closeRequestFcn);
screenunits=get(0,'units');set(0,'units','characters');screensize=get(0,'screensize');set(0,'units',screenunits);
set(hfig,'units','characters','position',[max(0,screensize(1,3:4)-[170,30])/2,170,30],'units','norm');

haxe=[];
hcolor=[];
htrans=[];
hcolors={};
set(hfig,'name','surf_show'); 
if 0,% chage to 1 and select the best option below for your machine/setup to improve quality of display
    if ispc, set(gcf,'WVisual','30'); end % (windows) 
    if isunix, set(gcf,'XVisual','0x23'); end % (unix)
end

if ~nargin % default surfaces
    surf_show_addfile(-1);
elseif isequal(varargin{1},'INITIALIZE')
    surf_show_addfile(-2);
    [SURFACES,LIGHTS,SURFACE_SELECTED,LIGHT_SELECTED,RESOLUTION,COLOR_BACKGROUND,CAMERA_HOLD,PRINT_OPTIONS]=deal(varargin{2:9});
else
    GUI=false;
    surf_show_commandline(varargin{:});
    GUI=true;
    if ~ishandle(hfig), return; end
end
surf_show_update;

%% main display function
    function surf_show_update(varargin)
        %figure(hfig);
        set(hfig,'pointer','watch'); %drawnow; 
        clf(hfig);
        h=get(hfig,'children');
        delete(h(ishandle(h)));
        haxe=gca;
        set(haxe,'units','norm','position',[.05,.05,.9,.9]);
        hires=RESOLUTION>1;
        DISPLAYED_SURFACES=[];
%         try
            SURFACE_GROUPS=zeros(1,numel(SURFACES));
            set(hfig,'color',COLOR_BACKGROUND);
            for n=1:numel(SURFACES)
                if ~SURFACE_GROUPS(n)&&(~isempty(SURFACES(n).show)&&SURFACES(n).show)&&(~strcmp(DOPRINT,'print_software')||PRINT_HOLOSELECT(n)),
                    switch SURFACES(n).material,
                        case 'normal',  mprop={'default','default','default','default','default'};
                        case 'emphasis',mprop={.1 .75 .5 1 .5};
                        case 'sketch',  mprop={.1 1 1 .25 0};
                        case 'shiny',   mprop={.3 .6 .9 20 1};
                        case 'dull',    mprop={.3 .8 0 10 1};
                        case 'metal',   mprop={.3 .3 1 25 .5};
                        otherwise,      mprop=num2cell(str2num(SURFACES(n).material));
                    end
                    if numel(mprop)<5, mprop=[mprop,repmat({'default'},1,5-numel(mprop))]; end
                    matchedsurfaces=find(arrayfun(@(i)all(cellfun(@(name)isequal(SURFACES(n).(name),SURFACES(i).(name)),{'offset','scale','patch'})),1:numel(SURFACES)));
                    color_combined=[];
                    trans_combined=[];
                    for i=matchedsurfaces
                        if ~isfield(SURFACES(i),'transparencyrange'), SURFACES(i).transparencyrange=[]; end
                        if ~isfield(SURFACES(i),'histogramequalization')||isempty(SURFACES(i).histogramequalization), SURFACES(i).histogramequalization=0; end
                        if ~isfield(SURFACES(i),'showborders')||isempty(SURFACES(i).showborders), SURFACES(i).showborders=0; end
                        color=[];
                        if hires,p=SURFACES(i).patch; c=SURFACES(i).rois;
                        else p=SURFACES(i).reducedpatch; c=SURFACES(i).reducedrois;
                        end
                        colorauto=~isempty(strfind(SURFACES(i).color,'auto'));
                        if size(c,2)==1, removevalues=surf_show_interprettransparencyrange(c,SURFACES(i).transparencyrange);
                        else removevalues=false(size(c,1),1);
                        end
                        if size(c,2)==3 %rgb
                            if colorauto||~isequal(size(str2num(SURFACES(i).color)),[1,3]), color=c;
                            else color=str2num(SURFACES(i).color);
                            end
                        elseif colorauto
                            if isempty(SURFACES(i).roicolors), color=[1 1 1];
                            else
                                tc=max(1,min(size(SURFACES(i).roicolors,1), SURFACES(i).roicolorscale(1)+c*SURFACES(i).roicolorscale(2) ));
                                if isequal(SURFACES(i).histogramequalization,1)||numel(SURFACES(i).histogramequalization)==2,
                                    tc=surf_show_histogramequalization(SURFACES(i).histogramequalization,c,size(SURFACES(i).roicolors,1),~removevalues);
                                end
                                color=SURFACES(i).roicolors(round(tc),:);
                            end
                        else color=str2num(SURFACES(i).color);
                        end
                        if colorauto
                            try
                                color=feval(inline(SURFACES(i).color,'auto'),color);
                            end
                        end
                        if isempty(color)||size(color,2)~=3, color=[1 1 1]; end
                        if size(color,1)==1, color=repmat(color,[size(p.vertices,1),1]); end
                        if size(color,1)~=size(p.vertices,1),
                            tc=max(1,min(size(color,1), 1+(size(color,1)-1)*(SURFACES(i).roicolorscale(1)+c*SURFACES(i).roicolorscale(2)-1)/255 ));
                            if isequal(SURFACES(i).histogramequalization,1)||numel(SURFACES(i).histogramequalization)==2,
                                tc=surf_show_histogramequalization(SURFACES(i).histogramequalization,c,size(color,1),~removevalues);
                            end
                            color=color(round(tc),:);
                        end
                        if SURFACES(i).showborders&&~isempty(SURFACES(i).rois)
                            if hires
                                if ~isfield(SURFACES(i),'roiborders')||isempty(SURFACES(i).roiborders)||numel(SURFACES(i).roiborders)~=size(c,1), SURFACES(i).roiborders=surf_show_computeborder(c,p.faces); end
                                rb=SURFACES(i).roiborders;
                            else
                                if ~isfield(SURFACES(i),'reducedroiborders')||isempty(SURFACES(i).reducedroiborders)||numel(SURFACES(i).reducedroiborders)~=size(c,1), SURFACES(i).reducedroiborders=surf_show_computeborder(c,p.faces); end
                                rb=SURFACES(i).reducedroiborders;
                            end
                            color(~rb|rb>SURFACES(i).showborders,:)=nan;
                        end
                        color(removevalues,:)=nan;
                        color_combined=cat(3,color_combined,color);
                        trans_combined=cat(1,trans_combined,SURFACES(i).transparency);
                        tcolor=color;
                        tcolor(isnan(tcolor))=0;
                        hcolors{i}=[sum(tcolor,1)./max(eps,sum(~isnan(color),1)),~isempty(SURFACES(i).paint)+2*(size(SURFACES(i).rois,2)>1)];
                    end
                    SURFACE_GROUPS(matchedsurfaces)=-n;
                    if numel(matchedsurfaces)==1,
                        trans=trans_combined;
                        color=color_combined;
                    else
                        isnancolor_combined=isnan(color_combined);
                        color_combined(isnancolor_combined)=0;
                        color=color_combined(:,:,1);
                        isnancolor=isnancolor_combined(:,:,1);
                        trans=trans_combined(1);%*~any(isnancolor,2);
                        for ncolor=2:size(color_combined,3)
                            w=min(~isnancolor_combined(:,:,ncolor),max(trans_combined(ncolor),isnancolor));
                            color=(1-w).*color+w.*color_combined(:,:,ncolor);
                            isnancolor=isnancolor&isnancolor_combined(:,:,ncolor);
                            %trans=max(trans,trans_combined(ncolor)*~any(isnancolor,2));
                        end
                        color(isnancolor)=nan;
%                         trans=max(trans_combined);
%                         isnancolor_combined=isnan(color_combined);
%                         color_combined(isnancolor_combined)=0;
%                         color=sum(bsxfun(@times,color_combined,shiftdim(trans_combined,-2)),3)./sum(bsxfun(@times,~isnancolor_combined,shiftdim(trans_combined,-2)),3);
                    end
                    %if numel(trans)>1&&max(trans(:))==min(trans(:)), trans=max(trans(:)); end
                    mp=mean(p.vertices,1);
                    p.vertices=bsxfun(@plus,mp+SURFACES(n).offset,bsxfun(@minus,p.vertices,mp)*SURFACES(n).scale);
                    p.faces=fliplr(p.faces);
                    phemright=mean(p.vertices(:,1)>0)>=.5;
                    transcolor=any(isnan(color),2);
                    color(transcolor,:)=1;
                    backfacelighting='reverselit'; %use 'lit' to remove edge effects or 'unlit' to discriminate internal/external faces 
                    if SHOWHEM==3||(SHOWHEM==1&&~phemright)||(SHOWHEM==2&&phemright)
                        if any(transcolor)||numel(trans)>1
                            h=patch(p,'edgecolor','none','facevertexcdata',double(color),...
                                'facecolor','interp','alphaDataMapping','none','facealpha','interp','facevertexalpha',max(.99*strcmp(DOPRINT,'print_software'),trans).*double(~transcolor),'FaceLighting', 'gouraud','BackFaceLighting',backfacelighting,...
                                'AmbientStrength', mprop{1},'DiffuseStrength',mprop{2},'SpecularStrength' ,mprop{3},  'SpecularExponent',mprop{4}, 'SpecularColorReflectance',mprop{5});
                        else
                            h=patch(p,'edgecolor','none','facevertexcdata',double(color),...
                                'facecolor','interp','alphadatamapping','none','facealpha',max(.99*strcmp(DOPRINT,'print_software'),trans),'FaceLighting', 'gouraud','BackFaceLighting',backfacelighting,...
                                'AmbientStrength', mprop{1},'DiffuseStrength',mprop{2},'SpecularStrength' ,mprop{3},  'SpecularExponent',mprop{4}, 'SpecularColorReflectance',mprop{5});
                        end
                        if CLICKTOSELECT>1,
                            set(h,'buttondownfcn',{@surf_show_clickselect,n},'interruptible','off');
                        end
                        DISPLAYED_SURFACES=[DISPLAYED_SURFACES,n]; 
                    end
                    SURFACE_GROUPS(n)=n;
                end
            end
            axis equal;
            view(VIEW.currentvalue);
            axis off tight;
            p=get(haxe,'cameraposition');
            for n=1:numel(LIGHTS)
                if LIGHTS(n).show,
                    position=p*strcmp(LIGHTS(n).reference,'viewer')+LIGHTS(n).position;
                    light('position',position,'color',LIGHTS(n).color,'style',LIGHTS(n).style);
                end
            end
            if ~isempty(CAMERA_HOLD), set(haxe,{'xlim','ylim','zlim'},CAMERA_HOLD); end
            lighting gouraud;
            switch DOPRINT
                case 'print', surf_show_print(varargin{:}); 
                case {'print_software','none_earlyreturn'}, return
            end
            set(haxe,'units','norm','position',[.05,.05,.6,.9]);
            hold on; ht=plot3(0,0,0,'ko','markerfacecolor','k','markeredgecolor','w','markersize',10); set(ht,'visible','off','buttondownfcn',{@surf_show_clickselect,n},'interruptible','off','tag','reference point'); hold off; 
%         catch
%             disp('Warning: Incorrect parameters');
%             disp(getfield(lasterror,'message'));
%         end
        
        uicontrol('style','frame','units','norm','position',[.69,.0,.31,1],'foregroundcolor',COLOR_BACKGROUND);
        uicontrol('style','frame','units','norm','position',[.69,.75,.31,.25],'foregroundcolor',COLOR_BACKGROUND);
        uicontrol('style','text','units','norm','position',[.7,.90,.09,.05],'string','View:','horizontalalignment','left','fontweight','bold');
        ht1=uicontrol('style','popupmenu','units','norm','position',[.80,.90,.18,.05],'string',VIEW.names,'value',VIEW.current,'interruptible','off','callback',@(varargin)surf_show_position,'tooltipString','Viewpoint specification');
        ht2=uicontrol('style','togglebutton','units','norm','position',[.7,.85,.09,.05],'string','Hold on','value',0,'interruptible','off','callback',@surf_show_camerahold,'tooltipString','Holds camera still (e.g. does not resize axes when adding/removing surfaces)');
        if ~isempty(CAMERA_HOLD), 
            set(ht1,'enable','off');
            set(ht2,'string','Hold off','value',1);
        end
        uicontrol('style','popupmenu','units','norm','position',[.7,.80,.09,.05],'string',{'Rotate','Select','Identify'},'value',CLICKTOSELECT,'interruptible','off','callback',@surf_show_clicktoselect,'tooltipString','<HTML>Controls the behavior when clicking on the image <br/> - <i>Rotate</i>: click-and-drag on the image to rotate the image view<br/> - <i>Select</i>: click on a surface to select this surface and identify a single vertex<br/> - <i>Identify</i>: click on the currently-selected surface to identify a single vertex</HTML>');
        uicontrol('style','popupmenu','units','norm','position',[.80,.85,.18,.05],'string',{'show left-hemisphere surfaces','show right-hemisphere surfaces','show all surfaces'},'value',SHOWHEM,'interruptible','off','callback',@(varargin)surf_show_hemisphere,'tooltipString','Select surfaces to be displayed');
        uicontrol('style','popupmenu','units','norm','position',[.80,.80,.18,.05],'string',{'low-resolution display','high-resolution display'},'value',min(2,RESOLUTION),'interruptible','off','callback',@(varargin)surf_show_resolution,'tooltipString','Select high-resolution for higher quality / low-resolution for faster performance');
        
        uicontrol('style','frame','units','norm','position',[.69,.40,.31,.38],'foregroundcolor',COLOR_BACKGROUND);
        uicontrol('style','text','units','norm','position',[.7,.70,.09,.05],'string','Surfaces:','horizontalalignment','left','fontweight','bold');
        if numel(SURFACES)
            ht=uicontrol('style','listbox','units','norm','position',[.8,.45,.18,.30],'string',{''},'max',2,'tooltipString','Select a surface','interruptible','off','callback',@surf_show_selectsurface,'tag','select_surface');
            tcolor=get(ht,'backgroundcolor')*.9;
            names=cellfun(@(a,b,c)sprintf('<HTML><FONT color=rgb(%d,%d,%d)>%s</FONT> <i>%s</i></HTML>',c*255*tcolor(1),c*255*tcolor(2),c*255*tcolor(3),a,b),{SURFACES.name},regexprep({SURFACES.paint},'(.+)','+ $1'),num2cell(SURFACE_GROUPS<0),'uni',0);
            set(ht,'string',names,'value',SURFACE_SELECTED);
            uicontrol('style','pushbutton','units','norm','position',[.70,.54,.09,.05],'string','Properties','interruptible','off','callback',@(varargin)surf_show_surfsettings,'tooltipString','Modifies selected surface properties');
            ht=uicontrol('style','pushbutton','units','norm','position',[.70,.49,.06,.05],'string','Paint','interruptible','off','callback',@(varargin)surf_show_addpaint,'tooltipString','Sets surface color from file (texturemap)  (right-click for default folders)');
            hc1=uicontextmenu;
            doneseparator=false;
            for ni=setdiff(1:numel(file_path),nfile_path+1:numel(file_path)-10)
                if ni>nfile_path&&~doneseparator, uimenu(hc1,'Label',file_path{ni},'interruptible','off','callback',@(varargin)surf_show_addpaint(file_path{ni}),'separator','on'); doneseparator=true;
                else uimenu(hc1,'Label',file_path{ni},'interruptible','off','callback',@(varargin)surf_show_addpaint(file_path{ni}));
                end
            end
            set(ht,'uicontextmenu',hc1);
            hcolor=uicontrol('style','pushbutton','units','norm','position',[.76,.49,.03,.05],'string','','interruptible','off','callback',@(varargin)surf_show_setcolor,'tooltipString','Sets surface color (uniform color)','visible','off');
            htrans=uicontrol('style','slider','units','norm','position',[.70,.44,.09,.045],'string','','interruptible','off','callback',@(varargin)surf_show_settrans,'tooltipString','Sets surface transparency','visible','off');
            uicontrol('style','pushbutton','units','norm','position',[.745,.65,.045,.05],'string','Delete','fontsize',11,'interruptible','off','callback',@surf_show_surfdel,'tooltipString','Removes selected surface from display');
            uicontrol('style','pushbutton','units','norm','position',[.98,.575,.02,.05],'string','','cdata',bsxfun(@times,shiftdim(tcolor/.9,-1),1-[0 0 0 0 0 0 0 0;0 0 0 0 0 0 0 0;0 0 0 1 1 0 0 0;0 0 1 0 0 1 0 0;0 1 0 0 0 0 1 0;1 0 0 0 0 0 0 1;0 0 0 0 0 0 0 0;0 0 0 0 0 0 0 0;]),'fontsize',11,'fontweight','bold','interruptible','off','callback',@surf_show_moveup,'tooltipString','Send backward (move paint up in the list)','tag','surf_show_moveup');
            uicontrol('style','pushbutton','units','norm','position',[.98,.525,.02,.05],'string','','cdata',bsxfun(@times,shiftdim(tcolor/.9,-1),flipud(1-[0 0 0 0 0 0 0 0;0 0 0 0 0 0 0 0;0 0 0 1 1 0 0 0;0 0 1 0 0 1 0 0;0 1 0 0 0 0 1 0;1 0 0 0 0 0 0 1;0 0 0 0 0 0 0 0;0 0 0 0 0 0 0 0;])),'fontsize',11,'fontweight','bold','interruptible','off','callback',@surf_show_movedown,'tooltipString','Bring forward (move paint down in the list)','tag','surf_show_movedown');
            ht=uicontrol('style','pushbutton','units','norm','position',[.7,.60,.045,.05],'string','Change','fontsize',11,'interruptible','off','callback',@(varargin)surf_show_surfadd([],'-change'),'tooltipString','Change surface file of selected surface(s) (right-click for default folders)');
            hc1=uicontextmenu;
            doneseparator=false;
            for ni=setdiff(1:numel(file_path),nfile_path+1:numel(file_path)-10)
                if ni>nfile_path&&~doneseparator, htuim=uimenu(hc1,'Label',file_path{ni},'interruptible','off','callback',@(varargin)surf_show_surfadd(file_path{ni},'-change'),'separator','on'); doneseparator=true;
                else htuim=uimenu(hc1,'Label',file_path{ni},'interruptible','off','callback',@(varargin)surf_show_surfadd(file_path{ni},'-change'));
                end
            end
            set(ht,'uicontextmenu',hc1);
            ht=uicontrol('style','pushbutton','units','norm','position',[.745,.60,.045,.05],'string','Copy','fontsize',11,'interruptible','off','callback',@(varargin)surf_show_surfadd([],'-copy'),'tooltipString','Duplicate selected surface(s)');
        end
        ht=uicontrol('style','pushbutton','units','norm','position',[.7,.65,.045,.05],'string','New','fontsize',11,'fontweight','bold','interruptible','off','callback',@(varargin)surf_show_surfadd,'tooltipString','Adds a new surface to display (right-click for default folders or manual x/y/z coordinates)');
        hc1=uicontextmenu;
        doneseparator=false;
        for ni=setdiff(1:numel(file_path),nfile_path+1:numel(file_path)-10)
            if ni>nfile_path&&~doneseparator, htuim=uimenu(hc1,'Label',file_path{ni},'interruptible','off','callback',@(varargin)surf_show_surfadd(file_path{ni}),'separator','on'); doneseparator=true; 
            else htuim=uimenu(hc1,'Label',file_path{ni},'interruptible','off','callback',@(varargin)surf_show_surfadd(file_path{ni}));
            end
        end
        set(htuim,'separator','on');
        uimenu(hc1,'Label','Manually defined x/y/z coordinates','interruptible','off','callback',@(varargin)surf_show_surfadd(0));
        set(ht,'uicontextmenu',hc1);
        
        uicontrol('style','frame','units','norm','position',[.69,.20,.31,.20],'foregroundcolor',COLOR_BACKGROUND);
        uicontrol('style','text','units','norm','position',[.7,.325,.09,.05],'string','Lights:','horizontalalignment','left','fontweight','bold');
        if numel(LIGHTS)
            uicontrol('style','listbox','units','norm','position',[.8,.225,.18,.15],'string',{LIGHTS.name},'value',LIGHT_SELECTED,'max',2,'tooltipString','Select a light-source','interruptible','off','callback',@surf_show_selectlight);
            uicontrol('style','pushbutton','units','norm','position',[.7,.215,.09,.05],'string','Properties','interruptible','off','callback',@(varargin)surf_show_lightsettings,'tooltipString','Modifies selected light-source properties');
            uicontrol('style','pushbutton','units','norm','position',[.745,.275,.045,.05],'string','Delete','fontsize',11,'interruptible','off','callback',@surf_show_lightdel,'tooltipString','Removes selected light-source from display');
        end
        uicontrol('style','pushbutton','units','norm','position',[.7,.275,.045,.05],'string','New','fontsize',11,'fontweight','bold','interruptible','off','callback',@surf_show_lightadd,'tooltipString','Adds a new light-source to display');
        
        uicontrol('style','frame','units','norm','position',[.69,.1,.31,.10],'foregroundcolor',COLOR_BACKGROUND);
        uicontrol('style','text','units','norm','position',[.7,.125,.09,.05],'string','Background:','horizontalalignment','left','fontweight','bold');
        uicontrol('style','pushbutton','units','norm','position',[.88,.125,.10,.05],'string','Properties','interruptible','off','callback',@(varargin)surf_show_backsettings,'tooltipString','Modifies background properties');
        
        uicontrol('style','frame','units','norm','position',[.69,.0,.31,.1],'foregroundcolor',COLOR_BACKGROUND);
        uicontrol('style','pushbutton','units','norm','position',[.70,.02,.09,.05],'string','Load','interruptible','off','callback',@surf_show_load,'tooltipString','Loads figure from file');
        uicontrol('style','pushbutton','units','norm','position',[.79,.02,.09,.05],'string','Save','interruptible','off','callback',@surf_show_save,'tooltipString','Saves current figure to file');
        uicontrol('style','pushbutton','units','norm','position',[.88,.02,.10,.05],'string','Print','interruptible','off','callback',@(varargin)surf_show_doprint,'tooltipString','Prints current figure to file');
        surf_show_update_selected;
        set(rotate3d,'ActionPostCallback',@surf_show_rotate);
        set(hfig,'userdata',{@surf_show_recover,SURFACES,LIGHTS,SURFACE_SELECTED,LIGHT_SELECTED,RESOLUTION,COLOR_BACKGROUND,CAMERA_HOLD,PRINT_OPTIONS});
        if CLICKTOSELECT==1&&isempty(CAMERA_HOLD), set(rotate3d,'enable','on'); else set(rotate3d,'enable','off'); end
        set(hfig,'pointer','arrow');
        drawnow;
        %if strcmp(get(hfig,'toolbar'),'none'), set(hfig,'toolbar','figure'); end
    end

    function surf_show_update_selected
        axis(haxe);
        h=findobj(haxe,'tag','tobedeleted');
        delete(h(ishandle(h)));
        hold on;
        for n=1:min(numel(SURFACE_SELECTED),numel(SURFACES))
            minmax=[min(SURFACES(SURFACE_SELECTED(n)).patch.vertices,[],1);max(SURFACES(SURFACE_SELECTED(n)).patch.vertices,[],1)];
            minmax=bsxfun(@plus,minmax(1,:),[0,0,0;0,0,1;0,1,1;0,1,0;0,0,0;1,0,0;1,0,1;1,1,1;1,1,0;1,0,0;1,1,0;0,1,0;0,1,1;1,1,1;1,0,1;0,0,1]*diag(minmax(2,:)-minmax(1,:)));
            mp=mean(SURFACES(SURFACE_SELECTED(n)).patch.vertices,1);
            minmax=bsxfun(@plus,mp+SURFACES(SURFACE_SELECTED(n)).offset,bsxfun(@minus,minmax,mp)*SURFACES(SURFACE_SELECTED(n)).scale);
            plot3(minmax(:,1),minmax(:,2),minmax(:,3),':','color',1-COLOR_BACKGROUND,'tag','tobedeleted');
        end
        hold off;
        if min(numel(SURFACE_SELECTED),numel(SURFACES))>0
            if ~isempty(hcolor)&&ishandle(hcolor)
                color=cell2mat(hcolors(SURFACE_SELECTED)');
                if isempty(color), color=[COLOR_BACKGROUND,0]; end
                if any(color(:,4)>1)
                    color2=cat(1,.5*ones(1,10,3),cat(2,.5*ones(8,1,3),repmat(~eye(8)&~flipud(eye(8)),[1,1,3]),.5*ones(8,1,3)),.5*ones(1,10,3));
                elseif any(color(:,4)==1)
                    color2=cat(1,.5*ones(1,10,3),cat(2,.5*ones(8,1,3),repmat(linspace(0,1,8)',[1,8,3]),.5*ones(8,1,3)),.5*ones(1,10,3));
                else
                    color2=color(round(linspace(1,size(color,1),8)),1:3);
                    color2=cat(1,.5*ones(1,10,3),cat(2,.5*ones(8,1,3),repmat(shiftdim(color2,-1),8,1),.5*ones(8,1,3)),.5*ones(1,10,3));
                end
                set(hcolor,'cdata',color2,'visible','on');
                if all(color(:,4)==1), set(hcolor,'callback',@surf_show_setcolorbar,'tooltipstring','Sets surface colormap');
                else set(hcolor,'callback',@(varargin)surf_show_setcolor,'tooltipstring','Sets surface color (uniform color)');
                end
            end
            if ~isempty(htrans)&&ishandle(htrans)
                trans=cell2mat({SURFACES(SURFACE_SELECTED).transparency});
                if isempty(trans), trans=1; end
                trans=mean(trans);
                set(htrans,'value',trans,'visible','on');
            end
        end
        if numel(SURFACE_SELECTED)==1&&numel(SURFACE_GROUPS)>0&&sum(abs(SURFACE_GROUPS)==abs(SURFACE_GROUPS(SURFACE_SELECTED)))>1
            moveup=findobj(hfig,'tag','surf_show_moveup');
            movedown=findobj(hfig,'tag','surf_show_movedown');
            idx=find(abs(SURFACE_GROUPS)==abs(SURFACE_GROUPS(SURFACE_SELECTED)));
            if idx(1)~=SURFACE_SELECTED, set(moveup,'visible','on'); else set(moveup,'visible','off'); end
            if idx(end)~=SURFACE_SELECTED, set(movedown,'visible','on'); else set(movedown,'visible','off'); end
        else
            set(findobj(hfig,'tag','surf_show_movedown'),'visible','off');
            set(findobj(hfig,'tag','surf_show_moveup'),'visible','off');
        end
    end



%% auxiliary functions

    function surf_show_surfsettings(varargin)
        if all(~cellfun('length',{SURFACES(SURFACE_SELECTED).rois})), 
            strcolor='Color ( [r g b] )'; 
        else
            strcolor='Color or Colormap ( [r g b] / jet / hsv / hot / copper / bone / ... / auto )'; 
        end
        if all(cellfun(@(a,b)~isempty(a)&size(b,2)==1,{SURFACES(SURFACE_SELECTED).paint},{SURFACES(SURFACE_SELECTED).rois})), 
            strtrans='Transparency range (range of paint values mapped to a transparent color)'; 
            strhiste='Colormap rescaling (0: none; 1: non-linear histogram equalization; [a b]: lower/upper colormap bounds)';
            strshowb='Show borders (0: show surfaces; 1: show borders; 2-4: show thicker borders)';
        else 
            strtrans=''; 
            strhiste='';
            strshowb='';
        end
        for i=1:numel(SURFACE_SELECTED)
            if ~isfield(SURFACES(SURFACE_SELECTED(i)),'transparencyrange'), SURFACES(SURFACE_SELECTED(i)).transparencyrange=[]; end
            if ~isfield(SURFACES(SURFACE_SELECTED(i)),'histogramequalization')||isempty(SURFACES(SURFACE_SELECTED(i)).histogramequalization), SURFACES(SURFACE_SELECTED(i)).histogramequalization=0; end
            if ~isfield(SURFACES(SURFACE_SELECTED(i)),'showborders')||isempty(SURFACES(SURFACE_SELECTED(i)).showborders), SURFACES(SURFACE_SELECTED(i)).showborders=0; end
            k=1;t=SURFACES(SURFACE_SELECTED(i)).material;           if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
            k=2;t=mat2str(SURFACES(SURFACE_SELECTED(i)).offset);    if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
            k=3;t=mat2str(SURFACES(SURFACE_SELECTED(i)).scale);     if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
            k=4;t=SURFACES(SURFACE_SELECTED(i)).color;              if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
            k=5;t=num2str(SURFACES(SURFACE_SELECTED(i)).transparency); if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
            k=6;t=(SURFACES(SURFACE_SELECTED(i)).transparencyrange); if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
            k=7;t=num2str(SURFACES(SURFACE_SELECTED(i)).histogramequalization); if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
            k=8;t=num2str(SURFACES(SURFACE_SELECTED(i)).showborders); if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
        end
        if ~ischar(answ{6}), answ{6}=num2str(answ{6}); end
        if ~nargin
            if isempty(strtrans)
                answ=inputdlg({ 'Material properties ( normal / shiny / dull / metal / emphasis / sketch / [ka kd ks n sc] ) see ''help material''', 'Position (offset in mm)','Size (scaling factor)',strcolor,'Transparency level ( 0-1 ) 0=not shown; 1=opaque'},...
                    ['surface ',sprintf('%s ',SURFACES(SURFACE_SELECTED).name)],1,answ(1:end-3));
            else
                answ=inputdlg({ 'Material properties ( normal / shiny / dull / metal / emphasis / sketch / [ka kd ks n sc] ) see ''help material''', 'Position (offset in mm)','Size (scaling factor)',strcolor,'Transparency level ( 0-1 ) 0=not shown; 1=opaque',strtrans,strhiste,strshowb},...
                    ['surface ',sprintf('%s ',SURFACES(SURFACE_SELECTED).name)],1,answ);
            end
        else
            params={'material','offset','scale','color','transparency','transparencyrange','histogramequalization','showborders'};
            answ=cell(1,numel(params));
            for k=1:numel(params), 
                i=strmatch(params{k},varargin(1:2:end),'exact');
                if ~isempty(i)
                    switch(k)
                        case {2,3,4}, if ~ischar(varargin{2*i(1)}), answ{k}=mat2str(varargin{2*i(1)}); end
                        case {5,7,8},     if ~ischar(varargin{2*i(1)}), answ{k}=num2str(varargin{2*i(1)}); end
                        case 6,     if ischar(varargin{2*i(1)}), answ{k}=varargin{2*i(1)}; else answ{k}=num2str(varargin{2*i(1)}); end
                        otherwise,  answ{k}=varargin{2*i(1)};
                    end
                end
            end
        end
        if ~isempty(answ)
            for i=1:numel(SURFACE_SELECTED)
                k=1;if ~isempty(answ{k}), SURFACES(SURFACE_SELECTED(i)).material=answ{k}; end
                k=2;if ~isempty(answ{k}), SURFACES(SURFACE_SELECTED(i)).offset=str2num(answ{k}); end
                k=3;if ~isempty(answ{k}), SURFACES(SURFACE_SELECTED(i)).scale=str2num(answ{k}); end
                k=4;if ~isempty(answ{k}), SURFACES(SURFACE_SELECTED(i)).color=answ{k}; try, temp=str2num(answ{k}); if isequal(size(temp),[numel(SURFACE_SELECTED),3]), SURFACES(SURFACE_SELECTED(i)).color=mat2str(temp(i,:)); end; end; end
                k=5;if ~isempty(answ{k}), SURFACES(SURFACE_SELECTED(i)).transparency=str2double(answ{k}); end
                k=6;if numel(answ)>=k&&~isempty(answ{k}), if ischar(answ{k})&& ~isempty(str2num(answ{k})), SURFACES(SURFACE_SELECTED(i)).transparencyrange=str2num(answ{k}); else SURFACES(SURFACE_SELECTED(i)).transparencyrange=answ{k}; end; end
                k=7;if numel(answ)>=k&&~isempty(answ{k}), if ischar(answ{k})&& ~isempty(str2num(answ{k})), SURFACES(SURFACE_SELECTED(i)).histogramequalization=str2num(answ{k}); else SURFACES(SURFACE_SELECTED(i)).histogramequalization=answ{k}; end; end
                k=8;if numel(answ)>=k&&~isempty(answ{k}), if ischar(answ{k})&& ~isempty(str2num(answ{k})), SURFACES(SURFACE_SELECTED(i)).showborders=str2num(answ{k}); else SURFACES(SURFACE_SELECTED(i)).showborders=answ{k}; end; end
                SURFACES(SURFACE_SELECTED(i)).show=SURFACES(SURFACE_SELECTED(i)).transparency>0;
            end
            if ~nargin, surf_show_update; end
        end
    end

    function rgb=surf_show_setcolor(rgb)
        %cp = com.mathworks.mlwidgets.graphics.ColorPicker(6,0,'');
        %set(cp,'Value',java.awt.color(1,0,0)
        %[jColorPicker,hContainer] = javacomponent(cp,[10,220,30,20],gcf);
        %set(cp,'ActionPerformedCallback',@(varargin)disp(get(cp,'ActionPerformedCallbackData')))
        %jColorPicker.getValue.getBlue
        if ~nargin, rgb=get(gcbo,'cdata'); end
        if isequal(size(rgb),[10,10,3])
            rgb=reshape(rgb(2:end-1,2:end-1,:),[64,3]);
            if any(any(diff(rgb,1,1))), rgb=[]; 
            else rgb=rgb(45,:); end
        end
        if isempty(rgb),rgb=uisetcolor;
        else rgb=uisetcolor(rgb);
        end
        if ~nargout&&~isequal(rgb,0)
            [SURFACES(SURFACE_SELECTED).color]=deal(mat2str(round(rgb(:)'*1000)/1000));
            surf_show_update;
        end
    end

    function surf_show_setcolorbar(varargin)
        for i=1:numel(SURFACE_SELECTED)
            t=SURFACES(SURFACE_SELECTED(i)).color;              
            t0=SURFACES(SURFACE_SELECTED(i)).rois;
            if size(t0,2)==1, t1=(SURFACES(SURFACE_SELECTED(i)).roicolorscale(1)+t0*SURFACES(SURFACE_SELECTED(i)).roicolorscale(2)-1)/255; else t1=[]; end
            t2=SURFACES(SURFACE_SELECTED(i)).transparencyrange;
            t3=SURFACES(SURFACE_SELECTED(i)).roicolorscale;
            t4=unique(SURFACES(SURFACE_SELECTED(i)).rois);
            if ~isfield(SURFACES(SURFACE_SELECTED(i)),'roinames'), SURFACES(SURFACE_SELECTED(i)).roinames=[]; end
            if ~isempty(SURFACES(SURFACE_SELECTED(i)).roinames)
                t5=SURFACES(SURFACE_SELECTED(i)).roinames(t4);
            else
                t5=[];
            end
            t6=SURFACES(SURFACE_SELECTED(i)).histogramequalization;
            t7=SURFACES(SURFACE_SELECTED(i)).showborders;
            if i==1,
                str=t; 
                str0=t0; 
                str1=t1; 
                str2=t2;
                str3=t3;
                str4=t4;
                str5=t5;
                str6=t6;
                str7=t7;
            else
                if ~isequal(str,t), str='';  end
                if ~isequal(str0,t0), str0=[];  end
                if ~isequal(str1,t1), str1=[];  end
                if ~isequal(str2,t2), str2=[];  end
                if ~isequal(str3,t3), str3=[];  end
                if ~isequal(str4,t4), str4=[];  end
                if ~isequal(str5,t5), str5=[];  end
                if ~isequal(str6,t6), str6=[];  end
                if ~isequal(str7,t7), str7=[];  end
            end
        end
        strorig=str;
        str=regexprep(strorig,'auto','jet(256)');
        if size(str2num(str),2)~=3, str='[1 1 1;0 0 0]'; end
        val2=~isempty(str2);
        val7=isequal(str7,1);
        val6=1+1*isequal(str6,1)+2*(numel(str6)==2);
        if ~val2, str2=0; end
        h=figure('name','Colorbar','numbertitle','off','menubar','none','color',COLOR_BACKGROUND,'units','characters','position',[max(0,screensize(3:4)-[55,30])/2,55,30],'units','norm');
        ha1=axes('units','norm','position',[.075,.25,.10,.5]);
        ha2=image(0);
        set(ha1,'ydir','normal','xtick',[],'ytick',[],'xcolor',1-COLOR_BACKGROUND,'ycolor',1-COLOR_BACKGROUND);
        axis tight;
        uicontrol('style','frame','units','norm','position',[.25,0,.75,1],'backgroundcolor',.94*[1 1 1],'foregroundcolor',.8*[1 1 1]);
        uicontrol('style','frame','units','norm','position',[.25,.1,.75,.8],'backgroundcolor',.94*[1 1 1],'foregroundcolor',.8*[1 1 1]);
        uicontrol('style','frame','units','norm','position',[.25,.35,.75,.9],'backgroundcolor',.94*[1 1 1],'foregroundcolor',.8*[1 1 1]);
        ht0=uicontrol('style','edit','string',strorig,'units','norm','position',[.30,.36,.53,.05],'backgroundcolor',.94*[1 1 1],'tooltipstring','Selected colorbar','callback',@(varargin)surf_show_setcolorbar_update);
        ht1=uicontrol('style','pushbutton','string','','units','norm','position',[.85,.36,.10,.05],'callback',@(varargin)surf_show_setcolorbar_update(@surf_show_setcolorbar_setcolor),'tooltipstring','Sets surface color to uniform color','cdata',cat(1,.5*ones(1,10,3),cat(2,.5*ones(8,1,3),ones(8,8,3),.5*ones(8,1,3)),.5*ones(1,10,3)));
        ht2=uicontrol('style','checkbox','string','Set transparency range','value',val2,'units','norm','position',[.30,.29,.65,.05],'backgroundcolor',.94*[1 1 1],'tooltipstring','Maps a range of painted values to a transparent color','callback',@(varargin)surf_show_setcolorbar_update);
        ht3=uicontrol('style','edit','string',num2str(str2),'units','norm','position',[.30,.23,.53,.05],'backgroundcolor',.94*[1 1 1],'tooltipstring','Range of values mapped to transparent color (e.g. ''x>100'' renders paint values above 100 as transparent; use single value ''n'' as a shorthand for ''x==n'', or two values ''n1 n2'' as a shorthand for ''x>=n1&x<=n2'')','callback',@(varargin)surf_show_setcolorbar_update);
        ht4=uicontrol('style','pushbutton','string','','units','norm','position',[.85,.23,.10,.05],'callback',@(varargin)surf_show_setcolorbar_settrans_manual(ht3),'tooltipstring','Select transparent values manually','cdata',cat(1,.5*ones(1,10,3),cat(2,.5*ones(8,1,3),ones(8,8,3),.5*ones(8,1,3)),.5*ones(1,10,3)));
        ht8=uicontrol('style','checkbox','string','Show borders only','value',val7,'units','norm','position',[.30,.17,.65,.05],'backgroundcolor',.94*[1 1 1],'tooltipstring','Shows only ROI boundaries (non-boundary areas set to transparent color)','callback',@(varargin)surf_show_setcolorbar_update);
        ht6=uicontrol('style','popupmenu','string',{'No effects','Histogram equalization (non-linear)','Histogram rescaling (linear)'},'value',val6,'units','norm','position',[.30,.11,.65,.05],'backgroundcolor',.94*[1 1 1],'tooltipstring','Modifies the association between paint values on the surface and colors in the colormap (non-linear histogram equalization; linear histogram rescaling)','callback',@(varargin)surf_show_setcolorbar_update);
        if val6==3, set(ht6,'userdata',str6); end
        ht7a=annotation('arrow','position',[get(ha1,'position')*[1 0;0 1;1 0;0 1]+[.02 0] -.01 0],'headstyle','plain','visible','off','buttondownfcn',@(varargin)surf_show_setcolorbar_mousemove(1,'on'));
        ht7b=annotation('arrow','position',[get(ha1,'position')*[1 0;0 1;1 0;0 1]+[.02 0] -.01 0],'headstyle','plain','visible','off','buttondownfcn',@(varargin)surf_show_setcolorbar_mousemove(2,'on'));
        %axes(ha1);
        %hold on; ht7a=plot([.5 1.5],[0 0],'w:','color',[.5 .5 .5],'linewidth',2,'visible','off'); ht7b=plot([.5 1.5],[0 0],'w:','color',[.5 .5 .5],'linewidth',2,'visible','off','buttondownfcn','disp(1)'); hold off;
        if ~val2, set(ht3,'enable','off'); end
        if ~val2||isempty(t4), set(ht4,'enable','off'); end
        if isempty(t5)&&numel(t4)>100, set(ht4,'visible','off'); end
        if isempty(t5), set(ht8,'visible','off'); end
        uicontrol('style','pushbutton','string','OK','units','norm','position',[.26,.01,.34,.08],'callback','uiresume');
        uicontrol('style','pushbutton','string','Cancel','units','norm','position',[.63,.01,.34,.08],'callback','delete(gcbf)');
        colors={'jet','hot','gray','hsv','pink','copper';'flipud(jet)','flipud(hot)','flipud(gray)','flipud(hsv)','flipud(pink)','flipud(copper)';'[0 0 1;1 0 0]','flipud(hot(2))','[1 1 1;.66 .66 .66]','[1 1 1;.33 .33 .33]','[1 1 1;0 0 0]',str};
        for n1=1:size(colors,1)
            for n2=1:size(colors,2)
                cmap=str2num(colors{n1,n2});
                ht=uicontrol('style','pushbutton','string','','units','norm','position',[.3+.55*(n2-1)/(size(colors,2)-1),1-.54*n1/size(colors,1),.5/size(colors,2),.44/size(colors,1)],'backgroundcolor','w','callback',@(varargin)surf_show_setcolorbar_update(@(varargin)set(ht0,'string',colors{n1,n2})),'tooltipstring',['Selects colorbar ',colors{n1,n2}]);
                set(ht,'units','pixels');pos=floor(get(ht,'position'));
                cmap=repmat(cmap(round(linspace(1,size(cmap,1),pos(4))),:),[1,1,pos(3)]);
                set(ht,'cdata',permute(cmap(end:-1:1,:,:),[1,3,2]),'units','norm');
            end
        end
        surf_show_setcolorbar_update;
        set(h,'units','pixels');
        uiwait(h);
        if ishandle(h)&&ishandle(ht0)
            str=get(ht0,'string');
            str2=get(ht3,'string');
            val2=get(ht2,'value');
            val6=get(ht6,'value');
            str6=get(ht6,'userdata');
            val7=get(ht8,'value');
            delete(h);
            if ~isempty(str)
                [SURFACES(SURFACE_SELECTED).color]=deal(str);
                if ~val2, str2=''; end
                temp=str2num(str2);
                if isempty(temp)&&~isempty(str2), temp=str2; end
                [SURFACES(SURFACE_SELECTED).transparencyrange]=deal(temp);
                switch val6
                    case 1, str6=0;
                    case 2, str6=1;
                    case 3, 
                end
                [SURFACES(SURFACE_SELECTED).histogramequalization]=deal(str6);
                [SURFACES(SURFACE_SELECTED).showborders]=deal(val7);
                surf_show_update;
            end
        end
        
        function surf_show_setcolorbar_setcolor(varargin)
            rgb=str2num(get(ht0,'string'));
            if size(rgb,1)>1||size(rgb,2)~=3, rgb=[]; end
            rgb=surf_show_setcolor(rgb);
            if ~isequal(rgb,0), 
                set(ht0,'string',mat2str(round(1000*rgb)/1000));
                set(ht1,'cdata',cat(1,.5*ones(1,10,3),cat(2,.5*ones(8,1,3),repmat(shiftdim(rgb,-1),[8,8,1]),.5*ones(8,1,3)),.5*ones(1,10,3)));
            end
        end
        
        function surf_show_setcolorbar_update(varargin)
            for n=1:nargin, feval(varargin{n}); end
            strorig=get(ht0,'string');
            str=regexprep(strorig,'auto','jet(256)');
            if size(str2num(str),2)~=3, str='[1 1 1;0 0 0]'; end
            rgb=str2num(str);
            if size(rgb,1)==1, rgb=repmat(rgb,2,1); end
            rgb=reshape(permute(repmat(rgb,[1 1 16]),[3 1 2]),[],size(rgb,2));
            temp=get(ht3,'string');
            str2=str2num(temp);
            if isempty(str2)&&~isempty(temp), str2=temp; end
            val2=get(ht2,'value');
            if ~val2, str2=[]; end
            if ~val2, set(ht3,'enable','off'); else set(ht3,'enable','on'); end
            if ~val2||isempty(t4), set(ht4,'enable','off'); else set(ht4,'enable','on'); end
            val6=get(ht6,'value');
            set(ha2,'cdata',permute(rgb(:,:,:),[1,3,2]));
            set(ha1,'ylim',[.5,size(rgb,1)+.5]);
            set([ht7a ht7b],'visible','off');
            if ~isempty(str3)
                sc0=linspace((1-str3(1))/str3(2),(256-str3(1))/str3(2),size(rgb,1))';
                sc=sc0;
                if ~isempty(t4), sc=[sc;t4]; end
                tc=surf_show_interprettransparencyrange(sc,str2);
                sc=max(1,min(size(rgb,1), 1+(size(rgb,1)-1)*(str3(1)+sc*str3(2)-1)/255 ));
                deleted=accumarray(round(sc),tc,[size(rgb,1),1])>0;
                temp=rgb;
                if val6==2&&~isempty(str0)
                    [nill,itemp,opt]=surf_show_histogramequalization(1,str0,size(rgb,1),~surf_show_interprettransparencyrange(str0,str2),sc0);
                    temp=temp(round(itemp),:);
                    %if ~isempty(str1), deleted=deleted|accumarray(round(max(1,min(size(rgb,1), 1+(size(rgb,1)-1)*str1 ))),1,[size(rgb,1),1])==0; end
                elseif val6==3&&~isempty(str0)
                    [nill,itemp,opt,iopt]=surf_show_histogramequalization(get(ht6,'userdata'),str0,size(rgb,1),~surf_show_interprettransparencyrange(str0,str2),sc0);
                    set(ht6,'userdata',opt);
                    set(ht7a,'position',get(ht7a,'position').*[1 0 1 1]+get(ha1,'position')*[0;1;0;iopt(1)]*[0 1 0 0],'visible','on','color',min(.8,rgb(1,:)));
                    set(ht7b,'position',get(ht7b,'position').*[1 0 1 1]+get(ha1,'position')*[0;1;0;iopt(min(numel(iopt),2))]*[0 1 0 0],'visible','on','color',min(.8,rgb(end,:)));
                    temp=temp(round(itemp),:);
                end
                temp(deleted,:)=repmat(COLOR_BACKGROUND,[nnz(deleted),1]);
                set(ha2,'cdata',permute(temp(:,:,:),[1,3,2]));
                xlabel(num2str(round((1-str3(1))/str3(2)*100)/100));
                title(num2str(round((256-str3(1))/str3(2)*100)/100),'color',1-COLOR_BACKGROUND);
                %set(ha1,'ytick',[.5,size(rgb,1)+.5],'yticklabel',cellstr(num2str(([255;1]-str3(1))/str3(2))));
            end
        end

        function surf_show_setcolorbar_settrans_manual(handle)
            temp4=t4;
            if isempty(t5)&&numel(temp4)>500, temp4=temp4(round(linspace(1,numel(temp4),500))); end
            if ~isempty(t5), temp5=t5; else temp5=num2str(temp4); end
            answ=listdlg('liststring',temp5,'selectionmode','multiple','initialvalue',find(surf_show_interprettransparencyrange(temp4,str2)),'promptstring','Select transparency values');
            if ~isempty(answ), 
                if numel(answ)==1, set(handle,'string',num2str(temp4(answ)));
                elseif sum(diff(answ)==1)>sum(diff(answ)>1), 
                    tidx=find(diff([-inf,answ,inf])>1);
                    set(handle,'string',num2str(reshape([floor(temp4(answ(tidx(1:end-1)))'*100)/100;ceil(temp4(answ(tidx(2:end)-1))'*100)/100],1,[])));
                else set(handle,'string',sprintf('ismember(x,[%s])',num2str(temp4(answ)')));
                end
                surf_show_setcolorbar_update;
            end
        end
        
        function surf_show_setcolorbar_mousemove(idx,opt)
            persistent oldunits;
            
            switch opt
                case 'on'
                    oldunits=get(0,'units');
                    set(0,'units','pixels');
                    set(gcf,'windowButtonMotionFcn',@(varargin)surf_show_setcolorbar_mousemove(idx,'move'),...
                            'windowButtonUpFcn',@(varargin)surf_show_setcolorbar_mousemove(idx,'off'));
                case 'move'
                    figpos=get(h,'position');
                    moupos=get(0,'pointerlocation');
                    colpos=get(ha1,'position');
                    rely=max(0,min(1, (moupos(2)-figpos(2)+1)/figpos(4) ));
                    k=(rely-colpos(2))/colpos(4);
                    if idx==1, set(ht7a,'position',get(ht7a,'position').*[1 0 1 1]+get(ha1,'position')*[0;1;0;k]*[0 1 0 0],'visible','on')
                    else,      set(ht7b,'position',get(ht7b,'position').*[1 0 1 1]+get(ha1,'position')*[0;1;0;k]*[0 1 0 0],'visible','on')
                    end
                case 'off'
                    str6=get(ht6,'userdata');
                    figpos=get(h,'position');
                    moupos=get(0,'pointerlocation');
                    colpos=get(ha1,'position');
                    rely=max(0,min(1, (moupos(2)-figpos(2)+1)/figpos(4) ));
                    k=(rely-colpos(2))/colpos(4);
                    str6(idx)=(1-str3(1))/str3(2)*(1-k) + (256-str3(1))/str3(2)*k;
                    set(ht6,'userdata',str6);
                    if ~isempty(oldunits), set(0,'units',oldunits); end
                    set(gcf,'windowButtonMotionFcn','','windowButtonUpFcn','');
                    surf_show_setcolorbar_update;
            end
        end
    end
        
    function surf_show_settrans(varargin)
        trans=get(gcbo,'value');
        [SURFACES(SURFACE_SELECTED).transparency]=deal(trans);
        surf_show_update;
    end

    function surf_show_moveup(varargin)
        SURFACES(SURFACE_SELECTED+[-1,0])=SURFACES(SURFACE_SELECTED+[0,-1]);
        SURFACE_SELECTED=SURFACE_SELECTED-1;
        surf_show_update;
    end
    function surf_show_movedown(varargin)
        SURFACES(SURFACE_SELECTED+[1,0])=SURFACES(SURFACE_SELECTED+[0,1]);
        SURFACE_SELECTED=SURFACE_SELECTED+1;
        surf_show_update;
    end

    function surf_show_addfile(filenames,varargin)
        if nargin>1&&any(strcmp(varargin,'-copy')),
            surf_show_addfile(SURFACES(SURFACE_SELECTED));
            return;
        end
        mfilename_path=fileparts(which(mfilename));
        dochange=false; 
        if nargin>1&&any(strcmp(varargin,'-change')),
            dochange=true;
            varargin=varargin(~strcmp(varargin,'-change'));
        end
        if nargin==1&&(isequal(filenames,-1)||isequal(filenames,-2)) % initialize
            opt=filenames;
            fprintf('Loading surfaces');
            filenames={'lh.pial.surf','rh.pial.surf'};
            for n1=1:numel(filenames)
                fprintf('.');
                xyz=read_surf(fullfile(mfilename_path,'surf',filenames{n1}));
                REF(n1).vertices=xyz;
                REF(n1).name=filenames{n1};
            end
            if isequal(opt,-1)
                filenames={'lh.pial.smoothed.surf','rh.pial.smoothed.surf','lh.subcortical.surf','rh.subcortical.surf'};
                for n1=1:numel(filenames)
                    fprintf('.');
                    surf_show_addfile(fullfile(mfilename_path,'surf',filenames{n1}));
                end
            end
            fprintf('\n');
            return
        end
        if ~nargin||dochange||(~isempty(filenames)&&ischar(filenames)&&isdir(filenames)) % loads file
            if ~nargin||~(~isempty(filenames)&&ischar(filenames)&&isdir(filenames)), filenames=file_path{end}; end
            [file_name,tfile_path]=uigetfile({'*.surf;*.img;*.nii;*.mgh;*.mgz;*.txt;*.xls;*.vtk;*.surfshow','All surface files (*.surf;*.img;*.nii;*.mgh;*.mgz;*.txt;*.xls;*.vtk;*.surfshow)';'*.surf', 'FreeSurfer surfaces (*.surf)'; '*.img;*.nii;*.mgh;*.mgz','Nifti volumes (*.img;*.nii;*.mgh;*.mgz)'; '*.txt;*.xls','Coordinate files (*.txt;*.xls)';'*.vtk','VTK files (*.vtk)';'*.surfshow','SurfShow files (*.surfshow)';'*','All files'},'Select a surface file',filenames,'multiselect','on');
            if isequal(file_name,0), return; end
            file_path{end+1}=regexprep(tfile_path,'[\\\/]$','');
            [nill,ifile_path]=unique(file_path,'last');
            file_path=file_path(union(ifile_path,1:nfile_path));
            file_name=cellstr(file_name);
            filenames=cellfun(@(x)fullfile(tfile_path,x),file_name,'uni',0);
        end
        if ischar(filenames), filenames=cellstr(filenames); end
        if ~iscell(filenames), filenames={filenames}; end
        ibak=numel(SURFACES);
        for nfile=1:numel(filenames)
            filename=filenames{nfile};
            if ischar(filename)
                [tfile_path,file_name,file_ext]=fileparts(filename);
                switch(file_ext)
                    case {'.txt','.xls'}
                        newp=surf_show_CreateVolume(filename);
                    case {'.img','.nii','.mgh','.mgz'}
                        if nargin<=1, newp=surf_volume(filename);
                        else          newp=surf_volume(filename,false,varargin{:});
                        end
                    case '.vtk'
                        newp=VTKread(filename);
                    case '.surfshow'
                        tmp=load(filename,'-mat');
                        names={tmp.SURFACES.name};
                        [select,ok]=listdlg('ListString',names,'SelectionMode','multiple','InitialValue',1:numel(names),'name','surf_show','PromptString','Import surfaces:');
                        newp=tmp.SURFACES(select);
                    otherwise % for other extensions assume freesurfer file
                        [xyz,faces]=read_surf(filename);
                        newp=struct('vertices',xyz,'faces',faces+1);
                end
            elseif isstruct(filename)
                newp=filename;
                filename=newp.filename;
                [tfile_path,file_name,file_ext]=fileparts(filename);
            else % manually-defined x/y/z coordinates
                manualcoords=inputdlg({'Enter x y z coordinates in mm (and optionally a fourth ''shape'' parameter -s/c/r/u/b- and a fifth ''size'' parameter)','File name (optional)'},'Manually-defined coordinates',[10 1]',{'','xyz-coordinates'});
                if isempty(manualcoords), return; end
                if isempty(manualcoords{2}), manualcoords{2}='xyz-coordinates'; end
                filename=manualcoords{2};
                [tfile_path,file_name,file_ext]=fileparts(filename);
                if ~isequal(file_ext,'.txt'), filename=fullfile(tfile_path,[file_name '.txt']); end
                manualcoords=regexp(cellstr(manualcoords{1}),'[\s,;]+','split');
                if ~strcmp(filename,'xyz-coordinates.txt')&&~isempty(dir(filename)),
                    warnansw=questdlg(['File ',filename,' already exist. Overwrite?'],'Warning!','Yes','No','Yes');
                    if ~isequal(warnansw,'Yes'), return; end
                end
                fh=fopen(filename,'wt');
                for n=1:numel(manualcoords),
                    if ~isempty(strfind(manualcoords{n}{1},'//'))
                        fprintf(fh,'%s ',manualcoords{n}{:});
                    elseif any(cellfun('length',regexp(manualcoords{n}(1:3),'[^\d\.-\+]'))),
                        fclose(fh); error('incorrect (non-numeric) x/y/z coordinates');
                    else
                        fprintf(fh,'%s %s %s ',manualcoords{n}{1},manualcoords{n}{2},manualcoords{n}{3});
                        if numel(manualcoords{n})>=4,
                            if any(cellfun('length',regexp(manualcoords{n}(4),'[^scrub]'))), fclose(fh); error('incorrect shape parameter'); end
                            fprintf(fh,'1 %s ',manualcoords{n}{4});
                        end
                        if numel(manualcoords{n})>=5,
                            if any(cellfun('length',regexp(manualcoords{n}(5),'[^\d\.-\+]'))), fclose(fh); error('incorrect (non-numeric) size parameter'); end
                            fprintf(fh,'%s ',manualcoords{n}{5:end});
                        end
                    end
                    fprintf(fh,'\n');
                end
                fclose(fh);
                newp=surf_show_CreateVolume(filename);
                [tfile_path,file_name,file_ext]=fileparts(filename);
            end
            if dochange,    inewsurf=SURFACE_SELECTED;
            else            inewsurf=numel(SURFACES)+(1:numel(newp));
            end
            if dochange&&numel(newp)==1&&numel(inewsurf)>1, newp=repmat(newp,1,numel(inewsurf)); end
            if numel(newp)~=numel(inewsurf), uiwait(errordlg('Mismatch between number of selected surfaces and number of new surfaces')); return; end
            if dochange
                for n=1:numel(newp)
                    if (isfield(newp(n),'patch')&&numel(SURFACES(inewsurf(n)).patch.vertices)~=numel(newp(n).patch.vertices))||(~isfield(newp(n),'patch')&&numel(SURFACES(inewsurf(n)).patch.vertices)~=numel(newp(n).vertices)), uiwait(errordlg('Mismatch between number of vertices in previous and new surfaces')); return; end
                end
            end
            for n=1:numel(newp)
                if isfield(newp(n),'patch'),
                    SURFACES(inewsurf(n)).patch=newp(n).patch;
                    for nf=fieldnames(newp(n))'
                        SURFACES(inewsurf(n)).(nf{1})=newp(n).(nf{1});
                    end
                else
                    SURFACES(inewsurf(n)).patch=newp(n);
                    SURFACES(inewsurf(n)).filename=filename;
                    if numel(newp)>1, SURFACES(inewsurf(n)).name=[file_name,file_ext,'_',num2str(n,'%03d')];
                    else SURFACES(inewsurf(n)).name=[file_name,file_ext];
                    end
                    if size(SURFACES(inewsurf(n)).patch.vertices,1)>1e4, SURFACES(inewsurf(n)).reducedpatch=reducepatch(SURFACES(inewsurf(n)).patch,1e4,'fast');
                    else SURFACES(inewsurf(n)).reducedpatch=SURFACES(inewsurf(n)).patch;
                    end
                    if ~dochange
                        SURFACES(inewsurf(n)).show=true;
                        SURFACES(inewsurf(n)).offset=[0 0 0];
                        SURFACES(inewsurf(n)).scale=1;
                        SURFACES(inewsurf(n)).color='auto';
                        SURFACES(inewsurf(n)).paint='';
                        SURFACES(inewsurf(n)).material='normal';
                        SURFACES(inewsurf(n)).transparency=1;
                        SURFACES(inewsurf(n)).transparencyrange=[];
                        SURFACES(inewsurf(n)).histogramequalization=0;
                        SURFACES(inewsurf(n)).rois=[];
                        SURFACES(inewsurf(n)).reducedrois=[];
                        SURFACES(inewsurf(n)).roicolors=[];
                        SURFACES(inewsurf(n)).roicolorscale=[0,1];
                        SURFACES(inewsurf(n)).roinames=[];
                        SURFACES(inewsurf(n)).roiborders=[];
                        SURFACES(inewsurf(n)).show=SURFACES(inewsurf(n)).transparency>0;
                    end
                end
            end
        end
        SURFACE_SELECTED=inewsurf; %min(numel(SURFACES),ibak+1):numel(SURFACES);
        if isempty(SURFACE_SELECTED), SURFACE_SELECTED=max(1,numel(SURFACES)); end
        try
            [nill,idx]=sort({SURFACES.name});
            SURFACES=SURFACES(idx);
            SURFACE_SELECTED=find(ismember(idx,SURFACE_SELECTED));
        end
    end

    function surf_show_addpaint(roifile,varargin)
        dorefresh=false;
        if ~nargin||(~isempty(roifile)&&ischar(roifile)&&isdir(roifile))
            dorefresh=true;
            if ~nargin, roifile=file_path{end}; end
            [tfile_name,tfile_path]=uigetfile({'*.paint;*.w;*.curv;*.rgb;*.img;*.nii;*.mgh;*.mgz;*.annot;*.mat;*.csv;*.xls;*.txt','All paint files (*.paint;*.w;*.curv;*.rgb;*.img;*.nii;*.mgh;*.mgz;*.annot;*.mat;*.csv;*.xls;*.txt)'; '*.paint;*.w;*.curv', 'FreeSurfer paint files (*.paint;*.w;*.curv)';  '*.rgb', 'Surface rgb values (*.rgb)'; '*.img;*.nii', 'Nifti surface files (*.img;*.nii)'; '*.img;*.nii;*.mgh;*.mgz', 'Nifti volume files (*.img;*.nii;*.mgh;*.mgz)';'*.annot','FreeSurfer annotation files (*.annot)';'*.mat','REX ROI-level analysis file (REX.mat)';'*.csv;*.xls;*.txt','Text-file ROI-level data (*.csv;*.xls;*.txt)'},...
                'Select a surface-color file',roifile);
            if ~isequal(tfile_name,0), 
                roifile=fullfile(tfile_path,tfile_name); 
                file_path{end+1}=regexprep(tfile_path,'[\\\/]$','');
                [nill,ifile_path]=unique(file_path,'last');
                file_path=file_path(union(ifile_path,1:nfile_path));
            else roifile=''; 
            end
        end
        if ~isempty(roifile)
            [nill,roifile_name,roifile_ext]=fileparts(roifile);
            explicitorder=nan;
            extracalls={};
            switch roifile_ext,
                case '.annot',
                    [temp_vert,temp_label,temp_table]=read_annotation(roifile,0);
                    [nill,temp_rois]=ismember(temp_label,temp_table.table(:,5));
                    temp_colors=temp_table.table(:,1:3)/255;
                    temp_scale=[0,1];
                    temp_names=temp_table.struct_names;
                case '.rgb',
                    fh=fopen(roifile,'rb');
                    temp_rois=double(reshape(fread(fh,inf,'uint8'),[],3))/255;
                    fclose(fh);
                    temp_colors=[];
                    temp_scale=[0,1];
                    temp_names={};
                case {'.img','.nii','.mgh','.mgz'}
                    temp_rois=MRIread(roifile,true);
                    nvox=prod(temp_rois.volsize);
                    if any(arrayfun(@(i)any(nvox==[1,2]*size(SURFACES(i).patch.vertices,1)),SURFACE_SELECTED)) % nifti surface files
                        %temp_rois=MRIread(roifile);
                        %temp_rois=permute(temp_rois.vol,[2,1,3]);
                        if any(strcmp(roifile_ext,{'.mgh','.mgz'}))
                            roifile=surf_mgh2nii(roifile);
                        end
                        temp_rois=spm_read_vols(spm_vol(roifile));
                    else % nifti volume files (note: assumes all volumes/surfaces in MNI space)
                        if GUI
                            answ=questdlg('Paint file has incompatible dimensions. Would you like to extract from this nifti volume the values at the surface coordinates?','Import volume','Yes','No','Yes');
                            if ~strcmp(answ,'Yes'), return; end
                        end
                        if any(strcmp(roifile_ext,{'.mgh','.mgz'}))
                            roifile=surf_mgh2nii(roifile);
                        end
                        explicitorder=0;
                        smooth=3;
                        vol=spm_vol(roifile);
                        temp_rois=[];
                        for i=1:numel(SURFACE_SELECTED)
                            data_ref=surf_extract(vol,SURFACES(SURFACE_SELECTED(i)).filename,'',smooth,GUI);
                            if isempty(data_ref), return; end
                            temp_rois=[temp_rois;data_ref(:)];
                        end
                        %temp_rois=surf_extract(fileparts(which(mfilename)),roifile,{'.white.surf','.pial.surf','.sphere.reg.surf'},true);
                    end
                    temp_rois=temp_rois(:);
                    temp_colors=jet(256);
                    temp_max=[min(temp_rois),max(temp_rois)];
                    fprintf('Imported values from %s: range %f to %f\n',roifile,temp_max(1),temp_max(2));
                    if temp_max(1)<0&&temp_max(2)>0&&max(abs(temp_max))/min(abs(temp_max))<1e3,  temp_scale=[128.5,127.5./max(eps,max(abs(temp_max)))];
                    else temp_scale=[1-255/max(eps,diff(temp_max))*temp_max(1),255/max(eps,diff(temp_max))];
                    end
                    temp_names={};
                case '.mat' % REX.mat ROI-level analysis file
                    temp=load(roifile);
                    nvox=prod(temp.params.VF(1).dim);
                    nrois=numel(temp.params.results.ROI_name);
                    %if any(arrayfun(@(i)any(nvox==[1,2]*size(SURFACES(i).patch.vertices,1)),SURFACE_SELECTED)) % nifti surface files
                    thfig=figure('units','norm','position',[.4,.4,.3,.4],'color','w','name','Display ROI-level analysis results','numbertitle','off','menubar','none');
                    uicontrol('style','text','units','norm','position',[0,.9,1,.1],'string',sprintf('%s (%d ROIs)',temp.params.results.contrast_name{1},nrois));
                    ht1=uicontrol('style','popupmenu','units','norm','position',[.10,.75,.80,.05],'string',{'Display stat values','Display beta values'},'value',1,'tooltipstring','Choose values to be plotted on the surface: stat values (T/F statistics) or beta values (effect sizes)');
                    ht0=uicontrol('style','checkbox','units','norm','position',[.10,.65,.80,.05],'string','Display all ROIs','backgroundcolor','w','horizontalalignment','left','value',1,'enable','on','tooltipstring','Display values from all ROIs in ROI-level analyses (or select a subset of ROIs; non-included ROIs are assigned a value of 0)');
                    ht0a=uicontrol('style','listbox','units','norm','position',[.20,.35,.70,.30],'string',temp.params.results.ROI_name,'max',2,'value',1,'enable','off','tooltipstring','Choose ROIs to be displayed');
                    ht2=uicontrol('style','checkbox','units','norm','position',[.10,.25,.80,.05],'string','Threshold ROI-level results','backgroundcolor','w','horizontalalignment','left','value',0,'enable','on','tooltipstring','Choose ROI-level threshold (non-signficant ROIs are assigned a value of 0)');
                    ht2a=uicontrol('style','popupmenu','units','norm','position',[.20,.20,.45,.05],'string',{'p-uncorrected < ','p-FDR < '},'value',2,'enable','off');
                    ht2b=uicontrol('style','edit','units','norm','position',[.65,.20,.25,.05],'string','.05','enable','off');
                    uicontrol('style','pushbutton','string','OK','units','norm','position',[.1,.01,.38,.10],'callback','uiresume');
                    uicontrol('style','pushbutton','string','Cancel','units','norm','position',[.51,.01,.38,.10],'callback','delete(gcbf)');
                    set(ht0,'callback',@(varargin)set([ht0a],'enable',subsref({'on','off'},struct('type','{}','subs',{{1+get(gcbo,'value')}}))));
                    set(ht2,'callback',@(varargin)set([ht2a,ht2b],'enable',subsref({'off','on'},struct('type','{}','subs',{{1+get(gcbo,'value')}}))));
                    if size(temp.params.results.beta,1)>1, set(ht1,'enable','off'); end
                    uiwait(thfig);
                    if ~ishandle(thfig), return; end
                    temp_measure=get(ht1,'value');
                    if get(ht2,'value')
                        temp_thresholdvalue=str2num(get(ht2b,'string'));
                        temp_thresholdtype=get(ht2a,'value');
                    else
                        temp_thresholdtype=0;
                    end
                    if get(ht0,'value'), validrois=ones(1,nrois);
                    else validrois=zeros(1,nrois); validrois(get(ht0a,'value'))=1; 
                    end
                    delete(thfig);
                    temp_rois=zeros(nvox,1);
                    imat=pinv(temp.params.VF(1).mat);
                    n1=0; n0=0;
                    for nroi=1:length(temp.params.ROIinfo.voxels),
                        for ncluster=1:length(temp.params.ROIinfo.voxels{nroi})
                            n1=n1+1;
                            if validrois(n1)&&(~temp_thresholdtype||(temp_thresholdtype==1&&temp.params.results.p_unc(1,n1)<=temp_thresholdvalue)||(temp_thresholdtype==2&&temp.params.results.p_FDR(1,n1)<=temp_thresholdvalue))
                                n0=n0+1;
                                xyz=round([temp.params.ROIinfo.voxels{nroi}{ncluster} ones(size(temp.params.ROIinfo.voxels{nroi}{ncluster},1),1)]*imat');
                                idx=1+(xyz(:,1:3)-1)*cumprod([1;temp.params.VF(1).dim(1:2)']);
                                if temp_measure==1, temp_rois(idx)=temp.params.results.T(1,n1);
                                else temp_rois(idx)=temp.params.results.beta(1,n1);
                                end
                            end
                        end
                    end
                    temp_colors=jet(256);
                    temp_max=[min(temp_rois),max(temp_rois)];
                    if temp_thresholdtype, fprintf('Imported %d supra-threshold ROI values\n',n0);
                    else fprintf('Imported %d ROI values\n',n0);
                    end
                    fprintf('Imported values from %s: range %f to %f\n',roifile,temp_max(1),temp_max(2));
                    if temp_max(1)<0&&temp_max(2)>0&&max(abs(temp_max))/min(abs(temp_max))<1e3,  temp_scale=[128.5,127.5./max(eps,max(abs(temp_max)))];
                    else temp_scale=[1-255/max(eps,diff(temp_max))*temp_max(1),255/max(eps,diff(temp_max))];
                    end
                    temp_names={}; %temp.params.ROInames;
                case {'.csv','.xls','.txt'} % Text-file ROI-level data
                    if strcmp(roifile_ext,'.csv')
                        [roinames,roivalues]=textread(roifile,'%s%d','delimiter',',');%,'headerlines',1);
                    elseif strcmp(roifile_ext,'.txt')
                        str=textread(roifile,'%s','delimiter','\n');
                        roinames=regexprep(str,'\s*\d*\.?\d*\s*$','');
                        roivalues=str2double(regexp(str,'\s*\d*\.?\d*\s*$','match','once'));
                    else
                        [roinames,roivalues]=xlsread(roifile);
                    end
                    if size(roivalues,1)==size(roinames,1), roivalues=roivalues(:,1);roinames=roinames(:,1);
                    elseif size(roivalues,1)==size(roinames,1)+1, roivalues=roivalues(2:end,1);roinames=roinames(:,1);
                    else disp(['file ',roifile,' format not recognized']); error('');
                    end
                    files1=dir(fullfile(fileparts(which(mfilename)),'surf','lh.*.annot'));
                    files2=dir(fullfile(fileparts(which(mfilename)),'surf','rh.*.annot'));
                    files=regexprep({files1(ismember(regexprep({files1.name},'^lh\.','rh.'),{files2.name})).name},'^lh\.','');
                    nrois=numel(roinames);
                    isleft=cellfun('length',regexpi(roinames,'\s*(\(?left\)?|\(l\))\s*'))>0;
                    isright=cellfun('length',regexpi(roinames,'\s*(\(?right\)?|\(r\))\s*'))>0;
                    if ~any(isleft|isright)&&numel(SURFACE_SELECTED)==1&&~isempty(regexp(SURFACES(SURFACE_SELECTED).name,'^lh\.|^rh\.'))
                        if ~isempty(regexp(SURFACES(SURFACE_SELECTED).name,'^lh\.')), basehem=1;
                        else basehem=2;
                        end
                    else basehem=3;
                    end
                    %if any(arrayfun(@(i)any(nvox==[1,2]*size(SURFACES(i).patch.vertices,1)),SURFACE_SELECTED)) % nifti surface files
                    thfig=figure('units','norm','position',[.4,.4,.3,.4],'color','w','name','Display ROI-level data','numbertitle','off','menubar','none');
                    uicontrol('style','text','units','norm','position',[0,.9,1,.1],'string',sprintf('%s (%d ROIs)',roifile,nrois));
                    ht0=uicontrol('style','checkbox','units','norm','position',[.10,.80,.80,.05],'string','Display all ROIs','backgroundcolor','w','horizontalalignment','left','value',1,'enable','on','tooltipstring','Display values from all ROIs in ROI-level analyses (or select a subset of ROIs; non-included ROIs are assigned a value of 0)');
                    ht0a=uicontrol('style','listbox','units','norm','position',[.20,.50,.70,.30],'string',roinames,'max',2,'value',1,'enable','off','tooltipstring','Choose ROIs to be displayed');
                    ht2=uicontrol('style','popupmenu','units','norm','position',[.10,.40,.80,.05],'string',{'left-hemisphere ROIs','right-hemisphere ROIs','hemisphere specified in ROI-name string'},'value',basehem,'tooltipstring','<HTML>Select ROI hemisphere<br/> - <i>hemisphere specified in ROI-name</i> looks for ''left, right, (left), (right), (L) or (R)'' words in ROI-names to determine the appropriate hemisphere</HTML>');
                    ht1=uicontrol('style','popupmenu','units','norm','position',[.10,.325,.80,.05],'string',files,'value',numel(files),'tooltipstring','Choose reference ROI-definition file to match ROI-names');
                    ht3=uicontrol('style','checkbox','units','norm','position',[.10,.25,.80,.05],'string','Display ROI borders','backgroundcolor','w','value',0,'tooltipstring','Creates and additional paint including the ROI boundaries of the selected ROIs');
                    uicontrol('style','pushbutton','string','OK','units','norm','position',[.1,.01,.38,.10],'callback','uiresume');
                    uicontrol('style','pushbutton','string','Cancel','units','norm','position',[.51,.01,.38,.10],'callback','delete(gcbf)');
                    set(ht0,'callback',@(varargin)set([ht0a],'enable',subsref({'on','off'},struct('type','{}','subs',{{1+get(gcbo,'value')}}))));
                    uiwait(thfig);
                    if ~ishandle(thfig), return; end
                    if get(ht0,'value'), validrois=ones(1,nrois);
                    else validrois=zeros(1,nrois); validrois(get(ht0a,'value'))=1; 
                    end
                    baseroifile=files{get(ht1,'value')};
                    basehem=get(ht2,'value');
                    addborders=get(ht3,'value');
                    delete(thfig);
                    baseroifiles={fullfile(fileparts(which(mfilename)),'surf',['lh.',baseroifile]), fullfile(fileparts(which(mfilename)),'surf',['rh.',baseroifile])};
                    [temp_vert,temp_label,temp_table]=read_annotation(baseroifiles{1},0);
                    [nill,temp_baserois1]=ismember(temp_label,temp_table.table(:,5));
                    temp_basenames1=temp_table.struct_names;
                    [temp_vert,temp_label,temp_table]=read_annotation(baseroifiles{2},0);
                    [nill,temp_baserois2]=ismember(temp_label,temp_table.table(:,5));
                    temp_basenames2=temp_table.struct_names;
                    nvox=2*size(temp_vert,1);
                    roinames=regexprep(roinames,'\s*(\(?left\)?|\(l\))\s*|\s*(\(?right\)?|\(r\))\s*','','ignorecase');
                    
                    importednames=zeros(0,2);
                    temp_rois=zeros(nvox,1);
                    n0=0;
                    for nroi=1:nrois,
                        if validrois(nroi)
                            [ok1,idx1]=ismember(roinames{nroi},temp_basenames1);
                            [ok2,idx2]=ismember(roinames{nroi},temp_basenames2);
                            if ok1&&((basehem==1&&~isright(nroi))||(basehem==3&&isleft(nroi)))
                                idx=find(temp_baserois1==idx1);
                                if ~isempty(idx)
                                    n0=n0+1;
                                    temp_rois(idx)=roivalues(nroi);
                                    importednames(n0,1)=idx1;
                                else 
                                    fprintf('Warning. ROI name %s matched in reference .annot file, but no vertices associated with this label\n',roinames{nroi});
                                end
                            elseif ok2&&((basehem==2&&~isleft(nroi))||(basehem==3&&isright(nroi)))
                                idx=find(temp_baserois2==idx2);
                                if ~isempty(idx)
                                    n0=n0+1;
                                    temp_rois(nvox/2+idx)=roivalues(nroi);
                                    importednames(n0,2)=idx2;
                                else 
                                    fprintf('Warning. ROI name %s matched in reference .annot file, but no vertices associated with this label\n',roinames{nroi});
                                end
                            else fprintf('ROI name %s not found in reference .annot file\n',roinames{nroi});
                            end
                        end
                    end
                    temp_colors=jet(256);
                    temp_max=[min(temp_rois),max(temp_rois)];
                    fprintf('Imported %d ROI values\n',n0);
                    fprintf('Imported values from %s: range %f to %f\n',roifile,temp_max(1),temp_max(2));
                    if temp_max(1)<0&&temp_max(2)>0&&max(abs(temp_max))/min(abs(temp_max))<1e3,  temp_scale=[128.5,127.5./max(eps,max(abs(temp_max)))];
                    else temp_scale=[1-255/max(eps,diff(temp_max))*temp_max(1),255/max(eps,diff(temp_max))];
                    end
                    temp_names={}; %temp.params.ROInames;
                    if addborders
                        if any(importednames(:,1)), 
                            extracalls{end+1}={'SURFACE_PAINT',baseroifiles{1},'SURFACE_PROPERTIES','color',[0 0 0],'transparencyrange',sprintf('ismember(x,%s)',mat2str(setdiff(1:numel(temp_basenames1),importednames(:,1)'))),'showborders',1};
                        end
                        if any(importednames(:,2)), 
                            extracalls{end+1}={'SURFACE_PAINT',baseroifiles{2},'SURFACE_PROPERTIES','color',[0 0 0],'transparencyrange',sprintf('ismember(x,%s)',mat2str(setdiff(1:numel(temp_basenames2),importednames(:,2)'))),'showborders',1};
                        end
                    end
                case {'.w','.W'} % paint .w file
                    [temp_vrois,temp_idx]=read_wfile(roifile);
                    temp_rois=zeros(size(SURFACES(SURFACE_SELECTED(1)).patch.vertices,1),1);
                    temp_rois(1+temp_idx)=temp_vrois;
                    temp_colors=jet(256);
                    temp_max=[min(temp_rois),max(temp_rois)];
                    fprintf('Imported values from %s: range %f to %f\n',roifile,temp_max(1),temp_max(2));
                    if temp_max(1)<0&&temp_max(2)>0&&max(abs(temp_max))/min(abs(temp_max))<1e3,  temp_scale=[128.5,127.5./max(eps,max(abs(temp_max)))];
                    else temp_scale=[1-255/max(eps,diff(temp_max))*temp_max(1),255/max(eps,diff(temp_max))];
                    end
                    temp_names={};
                otherwise, % paint (.paint .curv ..)
                    temp_rois=read_curv(roifile);
                    temp_colors=jet(256);
                    temp_max=[min(temp_rois),max(temp_rois)];
                    fprintf('Imported values from %s: range %f to %f\n',roifile,temp_max(1),temp_max(2));
                    if temp_max(1)<0&&temp_max(2)>0&&max(abs(temp_max))/min(abs(temp_max))<1e3,  temp_scale=[128.5,127.5./max(eps,max(abs(temp_max)))];
                    else temp_scale=[1-255/max(eps,diff(temp_max))*temp_max(1),255/max(eps,diff(temp_max))];
                    end
                    temp_names={};
            end
            answ='Replace';
            if all(cellfun('length',{SURFACES(SURFACE_SELECTED).paint}))
                if GUI
                    answ=questdlg('This surface already contains paint information. Do you want to add another paint or replace the existing paint information?','Paint surface','Add','Replace','Cancel','Add');
                    if isempty(answ)||strcmp(answ,'Cancel'), return; end
                else answ='Add'; 
                end
            elseif any(cellfun('length',{SURFACES(SURFACE_SELECTED).paint}))
                if GUI
                    answ=questdlg('Some, but not all, of these surfaces already contain paint information. Do you want to replace the existing paint information?','Paint surface','Replace','Cancel','Replace');
                    if isempty(answ)||strcmp(answ,'Cancel'), return; end
                else answ='Replace'; 
                end
            end
            if strcmp(answ,'Add')
                surf_show_addfile(SURFACES(SURFACE_SELECTED));
            end
            for i=1:numel(SURFACE_SELECTED)
                strroi=regexp(SURFACES(SURFACE_SELECTED(i)).name,'^(lh|rh)\.','tokens');
                if ~isempty(strroi), strroi=strroi{1}{1}; else strroi=''; end
                if isnan(explicitorder)&&isempty(strroi)&&size(temp_rois,1)==2*size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1)
                    uiwait(msgbox('Not possible to resolve hemisphere. Surface file should start with lh. or rh.'));
                elseif ~isnan(explicitorder)||size(temp_rois,1)==size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1)||size(temp_rois,1)==2*size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1)
                    SURFACES(SURFACE_SELECTED(i)).paint=[roifile_name,roifile_ext];
                    if ~isfield(SURFACES(SURFACE_SELECTED(i)),'color')||isempty(SURFACES(SURFACE_SELECTED(i)).color),%isempty(strfind(SURFACES(SURFACE_SELECTED(i)).color,'auto'))&&size(str2num(SURFACES(SURFACE_SELECTED(i)).color),1)==1
                        SURFACES(SURFACE_SELECTED(i)).color='auto';
                    end
                    keepvalues=strcmp(answ,'Replace')&&size(temp_rois,2)==1&&size(SURFACES(SURFACE_SELECTED(i)).rois,2)==1&&size(temp_colors,1)==size(SURFACES(SURFACE_SELECTED(i)).roicolors,1);
                    if ~isnan(explicitorder)
                        SURFACES(SURFACE_SELECTED(i)).rois=temp_rois(explicitorder+(1:size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1)),:);
                        explicitorder=explicitorder+size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1);
                    else
                        SURFACES(SURFACE_SELECTED(i)).rois=temp_rois((strcmp(strroi,'rh')&size(temp_rois,1)>size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1))*size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1)+(1:size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1)),:);
                    end
                    SURFACES(SURFACE_SELECTED(i)).roinames=temp_names;
                    if ~isempty(temp_names)
                        SURFACES(SURFACE_SELECTED(i)).roiborders=surf_show_computeborder(SURFACES(SURFACE_SELECTED(i)).rois,SURFACES(SURFACE_SELECTED(i)).patch.faces);
                    else
                        SURFACES(SURFACE_SELECTED(i)).roiborders=[];
                    end
                    SURFACES(SURFACE_SELECTED(i)).roicolorscale=temp_scale;
                    if ~keepvalues
                        SURFACES(SURFACE_SELECTED(i)).roicolors=temp_colors;
                        SURFACES(SURFACE_SELECTED(i)).transparencyrange=[];
                        SURFACES(SURFACE_SELECTED(i)).histogramequalization=0;
                    end
                    [ok,j]=ismember(SURFACES(SURFACE_SELECTED(i)).reducedpatch.vertices,SURFACES(SURFACE_SELECTED(i)).patch.vertices,'rows');
                    if all(ok), SURFACES(SURFACE_SELECTED(i)).reducedrois=SURFACES(SURFACE_SELECTED(i)).rois(j,:); end
                    if dorefresh&&isempty(extracalls), surf_show_update; end
                else
                    uiwait(msgbox(sprintf('Paint file has incompatible dimensions (%d; expected %d vertices)',size(temp_rois,1),size(SURFACES(SURFACE_SELECTED(i)).patch.vertices,1))));
                end
            end
            if ~isempty(extracalls)
                backGUI=GUI;
                GUI=false;
                for n1=1:numel(extracalls)
                    surf_show_commandline(extracalls{n1}{:});
                end
                GUI=backGUI;
                if dorefresh, surf_show_update; end
            end
        end
    end

    function surf_show_clickselect(varargin)
        if CLICKTOSELECT==3, nall=SURFACE_SELECTED(1);
        else nall=DISPLAYED_SURFACES;
        end
        p=get(gca,'cameraposition');
        p=p/norm(p);
        pos=get(gca,'currentpoint');
        pos=pos(1,1:3);
        errall=[];surfall=[];kall=[];idxall=[];
        dpts=2; % find vertices at less than this distance within each surface
        npts=10;% if none, consider the "npts" closest vertices within each surface
        for n=nall
            mp=mean(SURFACES(n).patch.vertices,1);
            x=bsxfun(@plus,mp+SURFACES(n).offset,bsxfun(@minus,SURFACES(n).patch.vertices,mp)*SURFACES(n).scale);
            k=x*p'-pos*p';
            err=sqrt(sum(bsxfun(@plus,pos,k*p-x).^2,2));
            idx1=find(err<dpts);
            npts1=numel(idx1);
            dbase=0;
            if ~npts1
                npts1=min(npts,numel(err));
                [sorterr,idx1]=sort(err);
                dbase=1e6;
            end
            idxall=[idxall;idx1(1:npts1)];
            errall=[errall;dbase+err(idx1(1:npts1))];
            surfall=[surfall;n+zeros(npts1,1)];
            kall=[kall;k(idx1(1:npts1))];
        end
        [minerr,idx2]=min(errall-1*kall);
        minerr=errall(idx2);
        n=surfall(idx2);
        idx=idxall(idx2);
        x1=SURFACES(n).patch.vertices(idx,:);
        mp=mean(SURFACES(n).patch.vertices,1);
        x2=mp+SURFACES(n).offset+(SURFACES(n).patch.vertices(idx,:)-mp)*SURFACES(n).scale;
        if ~isempty(REF)&&size(SURFACES(n).patch.vertices,1)==size(REF(1).vertices,1)&&~isempty(regexp(SURFACES(n).name,'^lh\.'))
            x3=REF(1).vertices(idx,:);
        elseif ~isempty(REF)&&size(SURFACES(n).patch.vertices,1)==size(REF(2).vertices,1)&&~isempty(regexp(SURFACES(n).name,'^rh\.'))
            x3=REF(2).vertices(idx,:);
        else x3=[];
        end
        if minerr>2, disp(sprintf('WARNING!!! Selected vertex not near current surface (distance = %dmm)',round(rem(minerr,1e6)))); end
        str=sprintf(['Selected surface:       %s (%d ,%d ,%d)\n',...
            'Closest vertex:         #%d\n',...
            'Surface coordinates:    (%d, %d, %d)\n',...
            'Canvas coordinates:     (%d, %d, %d)\n'],...
            SURFACES(n).name,round(mp(1)),round(mp(2)),round(mp(3)),...
            idx,...
            round(x1(1)),round(x1(2)),round(x1(3)),...
            round(x2(1)),round(x2(2)),round(x2(3)));
        if ~isempty(x3), str=[str, sprintf(...
                'MNI (pial) coordinates: (%d, %d, %d)\n',...
                round(x3(1)),round(x3(2)),round(x3(3)))];
        end
        disp(str);
        h=findobj(gcbf,'tag','reference point');
        if numel(h)==1
            set(h,'xdata',x2(1),'ydata',x2(2),'zdata',x2(3),'visible','on');
        end
        SURFACE_SELECTED=n;
        h=findobj(gcbf,'tag','select_surface');
        if numel(h)==1
            set(h,'value',SURFACE_SELECTED);
        end
        surf_show_update_selected;
    end

    function surf_show_selectsurface(varargin)
        SURFACE_SELECTED=unique(max(1,get(gcbo,'value')));
        surf_show_update_selected;
        if strcmp(get(gcbf,'SelectionType'),'open'), surf_show_surfsettings; end
    end

    function surf_show_surfdel(varargin)
        SURFACES=SURFACES(setdiff(1:numel(SURFACES),SURFACE_SELECTED));
        SURFACE_SELECTED=unique(max(1,min(SURFACE_SELECTED(1),numel(SURFACES))));
        surf_show_update;
    end

    function surf_show_surfadd(varargin)
        surf_show_addfile(varargin{:});
        surf_show_update;
    end

    function surf_show_lightsettings(varargin)
        params={'color','position','reference','style','enable'};
        answ=cell(1,numel(params));
        for i=1:numel(LIGHT_SELECTED)
            for k=1:numel(params)
                t=LIGHTS(LIGHT_SELECTED(i)).(params{k}); 
                switch(k)
                    case {1,2}, t=mat2str(t);
                end
                if i==1,answ{k}=t; elseif ~isequal(answ{k},t), answ{k}=''; end
            end
        end
        if ~nargin
            answ=inputdlg({'Light color ( [r g b] )','Light position ( [x y z] )', 'Light position reference-frame ( viewer / static )','Light-source distance ( infinite / local )','Enable light-source ( on / off )'},...
                'light settings',1,...
                answ);
        else
            for k=1:numel(params), 
                i=strmatch(params{k},varargin(1:2:end),'exact');
                if ~isempty(i)
                    switch(i(1))
                        case {1,2}, answ{k}=num2str(varargin{2*i(1)});
                        otherwise,  answ{k}=varargin{2*i(1)};
                    end
                end
            end
        end
        if ~isempty(answ)
            if ~isempty(answ{1}), [LIGHTS(LIGHT_SELECTED).color]=deal(str2num(answ{1})); end
            if ~isempty(answ{2}), [LIGHTS(LIGHT_SELECTED).position]=deal(str2num(answ{2})); end
            if ~isempty(answ{3}), [LIGHTS(LIGHT_SELECTED).reference]=deal(answ{3}); end
            if ~isempty(answ{4}), [LIGHTS(LIGHT_SELECTED).style]=deal(answ{4}); end
            if ~isempty(answ{5}), [LIGHTS(LIGHT_SELECTED).enable]=deal(answ{5}); end
            for i=1:numel(LIGHT_SELECTED)
                LIGHTS(LIGHT_SELECTED(i)).name=sprintf('%s %s',LIGHTS(LIGHT_SELECTED(i)).reference,mat2str(LIGHTS(LIGHT_SELECTED(i)).position,2));
                LIGHTS(LIGHT_SELECTED(i)).show=strcmp(LIGHTS(LIGHT_SELECTED(i)).enable,'on');
            end
            if ~nargin, surf_show_update; end
        end
    end

    function surf_show_addlight(varargin)
        LIGHTS(end+1).show=true;
        LIGHTS(end).color=[1 1 1];
        LIGHTS(end).position=[0 0 0];
        LIGHTS(end).reference='viewer';
        LIGHTS(end).style='infinite';
        LIGHTS(end).enable='on';
        for i=1:2:nargin-1, LIGHTS(end).(varargin{i})=varargin{i+1}; end
        LIGHTS(end).name=sprintf('%s %s',LIGHTS(end).reference,mat2str(LIGHTS(end).position,2));
        LIGHTS(end).show=strcmp(LIGHTS(end).enable,'on');
        LIGHT_SELECTED=max(1,numel(LIGHTS));
    end

    function surf_show_selectlight(varargin)
        LIGHT_SELECTED=max(1,get(gcbo,'value'));
        if strcmp(get(gcbf,'SelectionType'),'open'), surf_show_lightsettings; end
    end

    function surf_show_lightdel(varargin)
        LIGHTS=LIGHTS(setdiff(1:numel(LIGHTS),LIGHT_SELECTED));
        LIGHT_SELECTED=max(1,min(LIGHT_SELECTED,numel(LIGHTS)));
        surf_show_update;
    end

    function surf_show_lightadd(varargin)
        surf_show_addlight;
        surf_show_lightsettings;
    end

    function surf_show_backsettings(varargin)
        if ~nargin
            answ=inputdlg({'Background color ([r g b])'},...
                'background settings',1,...
                {mat2str(COLOR_BACKGROUND)});
        else
            params={'color'};
            answ=cell(1,numel(params));
            for k=1:numel(params), 
                i=strmatch(params{k},varargin(1:2:end),'exact');
                if ~isempty(i)
                    switch(i(1))
                        case 1,     answ{k}=mat2str(varargin{2*i(1)});
                        otherwise,  answ{k}=varargin{2*i(1)};
                    end
                end
            end
        end
        if ~isempty(answ)
            temp=str2num(answ{1});
            if numel(temp)==3, COLOR_BACKGROUND=temp; end
            if ~nargin, surf_show_update; end
        end
    end

    function surf_show_position(varargin)
        if nargin>0
            p=varargin{1};
            if ischar(p)||numel(p)==1
                if ischar(p), k=strmatch(p,VIEW.names,'exact');
                else          k=p;
                end
                if ~isempty(k)&&k(1)>0&&k(1)<=numel(VIEW.values)
                    VIEW.current=k(1);
                    VIEW.currentvalue=VIEW.values{VIEW.current};
                    VIEW.values{end}=VIEW.currentvalue;
                end
            elseif numel(p)==3
                VIEW.currentvalue=p./max(eps,sqrt(sum(p.^2)));
                VIEW.current=numel(VIEW.names);
                VIEW.values{VIEW.current}=VIEW.currentvalue;
            end
        else
            VIEW.current=get(gcbo,'value');
            VIEW.currentvalue=VIEW.values{VIEW.current};
            VIEW.values{end}=VIEW.currentvalue;
            if VIEW.current==numel(VIEW.names)
                answ=inputdlg({'View: 3-element vector containing [x,y,z] direction vector, or 2-element vector containing [az,el] direction in degrees','Standard View Name. This is an optional field. Filling a name here will store this view for future use. Using the special name ''remove'' (without quotes) will delete the last canonical view instead.'},...
                    'New view settings',1,...
                    {mat2str(VIEW.currentvalue,3),''});
                if ~isempty(answ)
                    t=str2num(answ{1});
                    if strcmp(answ{2},'remove')
                        VIEW.current=numel(VIEW.names)-1;
                        VIEW.currentvalue=VIEW.values{VIEW.current};
                        VIEW.names=VIEW.names(1:end-1);
                        VIEW.values=VIEW.values(1:end-1);
                        VIEW.names{end}='* new canonical view *';
                        current=VIEW.current;currentvalue=VIEW.currentvalue;values=VIEW.values;names=VIEW.names;
                        save(fullfile(fileparts(mfilename),'surf_show.mat'),'current','currentvalue','values','names');
                    elseif isequal(size(t),[1 3])||isequal(size(t),[1 2])||isequal(size(t),[4 4])
                        VIEW.currentvalue=t;
                        VIEW.values{VIEW.current}=t;
                        if ~isempty(answ{2})
                            VIEW.names{VIEW.current}=answ{2};
                            VIEW.names{VIEW.current+1}='* new canonical view *';
                            VIEW.values{VIEW.current+1}=VIEW.currentvalue;
                            current=VIEW.current;currentvalue=VIEW.currentvalue;values=VIEW.values;names=VIEW.names;
                            save(fullfile(fileparts(mfilename),'surf_show.mat'),'current','currentvalue','values','names');
                        end
                    end
                end
            end
            surf_show_update;
        end
    end

    function surf_show_resolution(varargin)
        if ~nargin
            RESOLUTION=get(gcbo,'value');
            surf_show_update;
        else
            RESOLUTION=varargin{1};
        end
    end

    function surf_show_hemisphere(varargin)
        SHOWHEM=get(gcbo,'value');
        surf_show_update;
    end

    function surf_show_rotate(varargin)
        p=get(gca,'cameraposition');
        VIEW.currentvalue=p./max(eps,sqrt(sum(p.^2)));
        VIEW.current=numel(VIEW.names);
        VIEW.values{VIEW.current}=VIEW.currentvalue;
        surf_show_update;
    end

    function surf_show_clicktoselect(varargin)
        CLICKTOSELECT=get(gcbo,'value');
        surf_show_update;
    end
        
    function surf_show_camerahold(varargin)
        if get(gcbo,'value'), CAMERA_HOLD=get(gca,{'xlim','ylim','zlim'});
        else CAMERA_HOLD={};
        end
        surf_show_update;
    end

    function surf_show_save(varargin)
        old_save_path=save_path;
        [save_name,save_path]=uiputfile({'*.surfshow','surf_show files (*.surfshow)';},'Select a figure file',save_path);
        if ~ischar(save_name), save_path=old_save_path; return; end
        save(fullfile(save_path,save_name),'SURFACES','LIGHTS','SURFACE_SELECTED','LIGHT_SELECTED','RESOLUTION','COLOR_BACKGROUND','CAMERA_HOLD','PRINT_OPTIONS','-MAT');
        disp(['Saved file ',fullfile(save_path,save_name)]);
    end

    function surf_show_load(varargin)
        old_save_path=save_path;
        [save_name,save_path]=uigetfile({'*.surfshow','surf_show files (*.surfshow)';},'Select a figure file',save_path);
        if ~ischar(save_name), save_path=old_save_path; return; end
        t=load(fullfile(save_path,save_name),'SURFACES','LIGHTS','SURFACE_SELECTED','LIGHT_SELECTED','RESOLUTION','COLOR_BACKGROUND','CAMERA_HOLD','PRINT_OPTIONS','-MAT');
        SURFACES=t.SURFACES;LIGHTS=t.LIGHTS;SURFACE_SELECTED=t.SURFACE_SELECTED;LIGHT_SELECTED=t.LIGHT_SELECTED;RESOLUTION=t.RESOLUTION;COLOR_BACKGROUND=t.COLOR_BACKGROUND;CAMERA_HOLD=t.CAMERA_HOLD;PRINT_OPTIONS=t.PRINT_OPTIONS;
        surf_show_update;
    end

    function surf_show_doprint(varargin)
        DOPRINT='print';
        if RESOLUTION==1
            if GUI
                answ=questdlg('Use high-resolution surfaces for printing?', ...
                'print options', ...
                'Yes','No','Yes');
            else answ='Yes';
            end
            if strcmp(answ,'Yes'), RESOLUTION=3; end
        end
        surf_show_update(varargin{:});
    end

    function surf_show_print(varargin)
        backname=get(hfig,'name');
        backshowhem=SHOWHEM;
        backview=VIEW.current;
        set(hfig,'inverthardcopy','off','name','surf_show: Print preview');
        units=get(hfig,{'units','paperunits'});
        set(hfig,'units','points');
        set(hfig,'paperunits','points','paperpositionmode','manual','paperposition',get(hfig,'position'));
        set(hfig,{'units','paperunits'},units);
        answ={'print01.jpg','single',strtrim(sprintf('%s ',PRINT_OPTIONS{:})),'hardware'};
        if nargin
            params={'filename','view','options','renderer'};
            for k=1:2:nargin,
                i=strmatch(lower(varargin{k}),params,'exact');
                if ~isempty(i), answ{i(1)}=varargin{k+1}; end
            end
        else
            answ=inputdlg({'Output file','Print view (single / mosaic)','Print options (see ''help print'')','Transparency renderer ( hardware / software )'},...
                'print options',1,...
                answ);
        end
        if ~isempty(answ)
            filename=answ{1};
            PRINT_OPTIONS=regexp(strtrim(answ{3}),'\s+','split');
            ok=false;
            domosaic=strcmp(answ{2},'mosaic');
            dohardware=strcmp(answ{4},'hardware');
            domosaiccrop=true;
            if dohardware&&~domosaic
                drawnow;
                print(hfig,PRINT_OPTIONS{:},filename);
                ok=true;
            else
                back_camera_hold=CAMERA_HOLD;
                CAMERA_HOLD=get(gca,{'xlim','ylim','zlim'});
                if ~dohardware,
                    p=[SURFACES.transparency];
                    i=find(p>0&p<1);
                    n=numel(i);
                    if n<=6, k=ones(2^n,numel(p));k(:,i)=dec2bin(0:2^n-1,n)-'0'; p=prod(k(:,i)*diag(p(i))+(1-k(:,i))*diag(1-p(i)),2);
                    else     k=bsxfun(@lt,rand(64,numel(p)),p(:)'); p=ones(64,1);
                    end
                else p=1;
                end
                hw=waitbar(0,'Printing. Please wait...','createcancelbtn','set(gcbf,''userdata'',1);');
                set(hw,'handlevisibility','off','hittest','off','color','w');
                numj=1+3*domosaic;
                for j=1:numj
                    a{j}=0;
                    if domosaic
                        allpos=[1 2 2 1];
                        VIEW.current=allpos(j);
                        VIEW.currentvalue=VIEW.values{VIEW.current};
                        SHOWHEM=1+(j>=3);
                    end
                    for i=1:size(p,1)
                        if ~dohardware
                            DOPRINT='print_software';
                            PRINT_HOLOSELECT=k(i,:);
                        else
                            DOPRINT='none_earlyreturn';
                        end
                        surf_show_update;
                        drawnow;
                        print(hfig,PRINT_OPTIONS{:},filename);
                        b=imread(filename);
                        if isa(b,'uint8'), b=double(b)/255; end
                        if max(b(:))>1, b=double(b)/double(max(b(:))); end
                        a{j}=a{j}+p(i).*double(b);
                        set(hw,'handlevisibility','on');
                        waitbar((j-1+i/size(p,1))/numj,hw);
                        set(hw,'handlevisibility','off');
                        if isequal(get(hw,'userdata'),1), a{j}=0; break; end
                    end
                    if ~isequal(a{j},0)
                        a{j}=a{j}/sum(p);
                    else break;
                    end
                end
                if ~isequal(a{j},0)
                    if domosaic, 
                        if domosaiccrop
                            cropt=any(any(diff(a{1},1,2),2),3)|any(any(diff(a{3},1,2),2),3);
                            cropt_idx13=max(1,sum(~cumsum(cropt))-16):size(a{1},1)-max(0,sum(~cumsum(flipud(cropt)))-16);
                            cropt=any(any(diff(a{1},1,1),1),3)|any(any(diff(a{2},1,1),1),3);
                            cropt_idx12=max(1,sum(~cumsum(cropt))-16):size(a{1},2)-max(0,sum(~cumsum(flipud(cropt)))-16);
                            cropt=any(any(diff(a{2},1,2),2),3)|any(any(diff(a{4},1,2),2),3);
                            cropt_idx24=max(1,sum(~cumsum(cropt))-16):size(a{2},1)-max(0,sum(~cumsum(flipud(cropt)))-16);
                            cropt=any(any(diff(a{1},1,1),1),3)|any(any(diff(a{2},1,1),1),3);
                            cropt_idx34=max(1,sum(~cumsum(cropt))-16):size(a{3},2)-max(0,sum(~cumsum(flipud(cropt)))-16);
                            a=[a{1}(cropt_idx13,cropt_idx12,:),a{3}(cropt_idx13,cropt_idx34,:);a{2}(cropt_idx24,cropt_idx12,:),a{4}(cropt_idx24,cropt_idx34,:)];
                        else
                            a=[a{1},a{3};a{2},a{4}];
                        end
                    else a=a{1};
                    end
                    imwrite(a,filename);
                    ok=true;
                end
                CAMERA_HOLD=back_camera_hold;
                PRINT_HOLOSELECT=[];
                delete(hw);
            end
            if ok
                try
                    a=imread(filename);
                    hf=figure('name',['printed file ',filename],'numbertitle','off','color','w','tag','surf_show_figures');
                    imagesc(a); title(filename); axis equal tight; set(gca,'box','on','xtick',[],'ytick',[]); set(hf,'handlevisibility','off','hittest','off');
                catch
                    disp(['Saved file: ',filename]);
                end
                figure(hfig);
            end
        end
        VIEW.current=backview;
        VIEW.currentvalue=VIEW.values{VIEW.current};
        if RESOLUTION==3||strcmp(DOPRINT,'print_software')||SHOWHEM~=backshowhem,
            SHOWHEM=backshowhem;
            if RESOLUTION==3, RESOLUTION=1; end
            DOPRINT='none_earlyreturn';
            surf_show_update;
        end
        DOPRINT='none';
        set(hfig,'name',backname);
    end

    function surf_show_commandline(varargin) % process command-line arguments
        params={'SURFACE_ADD','SURFACE_PROPERTIES','SURFACE_PAINT','LIGHT_ADD','LIGHT_PROPERTIES','BACKGROUND_PROPERTIES','VIEW','RESOLUTION','PRINT','CLOSE'};
        funs={@surf_show_addfile,@surf_show_surfsettings,@surf_show_addpaint,@surf_show_addlight,@surf_show_lightsettings,@surf_show_backsettings,@surf_show_position,@surf_show_resolution,@surf_show_doprint,@(varargin)delete([hfig findall(0,'tag','surf_show_figures')])};
        idx=find(cellfun(@ischar,varargin));
        [ok,k]=ismember(varargin(idx),params);
        if ~any(ok)&&nargin>0&&~isempty(varargin{1}), varargin=[{'SURFACE_ADD'},varargin]; ok=1;idx=1;k=1; end
        idx=[idx(ok),numel(varargin)+1];
        k=k(ok);
        for i=1:numel(idx)-1
            ivarargin=idx(i)+1:idx(i+1)-1;
            funs{k(i)}(varargin{ivarargin});
        end
    end

    function surf_show_recover(varargin)
        if nargin
            [SURFACES,LIGHTS,SURFACE_SELECTED,LIGHT_SELECTED,RESOLUTION,COLOR_BACKGROUND,CAMERA_HOLD,PRINT_OPTIONS]=deal(varargin{1:8});
        end
        surf_show_update;
    end

    function surf_show_closeRequestFcn(varargin)
        answ=questdlg('Closing this figure will loose all unsaved progress. Do you want to:','Warning','Quit','Continue','Restore last working state','Quit');
        if isempty(answ), answ='Continue'; end
        switch(answ)
            case 'Quit',
                delete(findall(0,'tag','surf_show_figures'));
                try; delete(gcbf); end
            case 'Continue',
                surf_show_update;
            otherwise
                data=get(gcf,'userdata');
                surf_show('INITIALIZE',data{2:end});
                delete(gcbf);
        end
    end
        
    function newp=surf_show_CreateVolume(filename)
        persistent lastchoice;
        if isempty(lastchoice), lastchoice=''; end
        newp=CreateVolume('',filename,'');
        if numel(SURFACES)>0
            surffullnames=[{SURFACES.filename},{fullfile(mfilename,'surf','lh.pial.surf'),fullfile(mfilename,'surf','rh.pial.surf')}];
            surfnames=[{SURFACES.name}];%,{'lh.pial.surf','rh.pial.surf'}];
            [surfnames,surfidx]=unique(surfnames,'first');
            surffullnames=surffullnames(surfidx);
            [nill,value]=ismember(lastchoice,surfnames);
            value=value(value>0);
            if isempty(value)&&numel(surfnames)==1, value=1; end
            thfig=figure('units','norm','position',[.4,.5,.3,.2],'color','w','name','Transform spatial coordinates','numbertitle','off','menubar','none');
            ht3=uicontrol('style','checkbox','units','norm','position',[.15,.25,.75,.1],'string','Project to matched pial-surface vertices','backgroundcolor','w','horizontalalignment','left','value',0,'enable','off');
            ht1=uicontrol('style','listbox','units','norm','position',[.15,.35,.75,.45],'string',surfnames,'value',value,'max',2,'enable','off','callback',@(varargin)set(ht3,'enable',subsref({'off','on'},struct('type','{}','subs',{{1+all(ismember(surfnames(get(gcbo,'value')),{'lh.cortex.surf','lh.inflated.surf','lh.orig.surf','lh.pial.smoothed.surf','lh.pial.surf','lh.sphere.reg.surf','lh.sphere.surf','lh.white.surf','rh.cortex.surf','rh.inflated.surf','rh.orig.surf','rh.pial.smoothed.surf','rh.pial.surf','rh.sphere.reg.surf','rh.sphere.surf','rh.white.surf'}))}}))));
            ht2=uicontrol('style','checkbox','units','norm','position',[.1,.8,.8,.1],'string','Project coordinates to closest surface:','value',0,'backgroundcolor','w','horizontalalignment','left','callback',@(varargin)set([ht1 ht3],'enable',subsref({'off','on'},struct('type','{}','subs',{{get(gcbo,'value')+1}}))));
            uicontrol('style','pushbutton','string','OK','units','norm','position',[.1,.01,.38,.15],'callback','uiresume');
            uicontrol('style','pushbutton','string','Skip','units','norm','position',[.51,.01,.38,.15],'callback','delete(gcbf)');
            uiwait(thfig);
            if ishandle(thfig)
                if get(ht2,'value')
                    surfidx2=get(ht1,'value');
                    if isempty(surfidx2), disp('Warning. No projection surfaces selected. Skipping spatial transformation step'); 
                    else
                        lastchoice=surfnames(surfidx2);
                        filenames=surffullnames(surfidx2);
                        [mx,i]=surf_project(cell2mat(cellfun(@(x)mean(x,1),{newp.vertices}','uni',0)),filenames,get(ht3,'value')&strcmp(get(ht3,'enable'),'on'),{SURFACES(surfidx(surfidx2)).patch},{SURFACES(surfidx(surfidx2)).offset},{SURFACES(surfidx(surfidx2)).scale});
                        for ni=1:numel(newp),
                            tmx=mx(ni,:);
                            newp(ni).vertices=bsxfun(@plus,tmx-mean(newp(ni).vertices,1),newp(ni).vertices);
                        end
                    end
                end
                delete(thfig);
            end
        end
    end


end

function border=surf_show_computeborder(values,faces)
A=spm_mesh_adjacency(faces);
border=zeros(size(values));
for n1=1:numel(border), border(n1)=any(values(n1)~=values(A(:,n1)>0)); end
for n2=2:4, for n1=find(border==n2-1)'; border(~border&A(:,n1)>0)=n2; end; end
end

function y=surf_show_interprettransparencyrange(c,tr)
y=false(size(c));
if ischar(tr)
    try
        y=feval(inline(tr,'x'),c);
    end
elseif numel(tr)==1
    y=c==tr;
else
    for ni=1:2:numel(tr)-1
        y=y|c>=tr(ni)&c<=tr(ni+1);
    end
end
end

function [y,y2,opt,iopt]=surf_show_histogramequalization(opt,x,N,valid,x2);
if isequal(opt,1)||numel(opt)==2||isempty(opt)
    iopt=[];
    values=x(valid);
    [v,i]=sort(values);
    vv=true(size(v));
    if isequal(opt,1)
        w=linspace(1,N,numel(values));
    else
        if isempty(opt), opt=[min(v) max(v)]; end
        w=max(1,min(N, 1+(N-1)*(v-opt(1))/max(eps,opt(2)-opt(1)) ));
        iopt=1;
    end
    for n=(find(~diff(v(:)))')
        w(n+1)=w(n);
        vv(n+1)=false;
    end
    yt=zeros(size(i));
    yt(i)=w;
    y=repmat(N,size(x));
    y(valid)=yt;
    if nargin>3&&nargout>1
        if nnz(vv)==1, y2=repmat(v(vv),size(x2));
        else
            y2=max(1,min(N, interp1(v(vv),w(vv),x2,'linear','extrap') ));
%             y2=x2;
%             minv=min(v(vv));
%             maxv=max(v(vv));
%             y2(x2<=minv)=1;
%             y2(x2>=maxv)=N;
%             y2(x2>minv&x2<maxv)=interp1(v(vv),w(vv),x2(x2>minv&x2<maxv),'linear');
            if ~isempty(iopt), iopt=interp1(x2,linspace(0,1,numel(x2)),opt,'linear','extrap'); end
        end
    end
else
    error('invalid opt value');
end

end
