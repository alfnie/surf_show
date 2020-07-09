function p=surf_volume(filename,DODISP,THR,SMOOTH,DISREGARDZEROS,HEMSEPARATE,INDIVIDUALCLUSTERS)

if nargin<1||isempty(filename)
    [file_name,file_path]=uigetfile('*.img;*.nii;*.mgh;*.mgz','Select volume',pwd);
    if isequal(file_name,0), return; end
    filename=fullfile(file_path,file_name);
end
[file_path,file_name,ext]=spm_fileparts(filename);
if any(strcmp(ext(1:min(4,length(ext))),{'.mgh','.mgz'}))
    filename=surf_mgh2nii(filename);
end
VOL=spm_vol(filename);
DAT=spm_read_vols(VOL);
if nargin<2||isempty(DODISP), DODISP=true; end
if nargin<3||isempty(THR), THR=median(DAT(~isnan(DAT)&DAT~=0)); end
if nargin<4||isempty(SMOOTH), SMOOTH=5; end
if nargin<5||isempty(DISREGARDZEROS), DISREGARDZEROS=true; end
if nargin<6||isempty(HEMSEPARATE), HEMSEPARATE=false; end
if nargin<7||isempty(INDIVIDUALCLUSTERS), INDIVIDUALCLUSTERS=false; end
DOLOGHIST=false;
VIEW=[1 1 1];
OLDTHR=nan;
OLDSMOOTH=nan;
OLDDISREGARDZEROS=nan;
OLDHEMSEPARATE=nan;
OLDINDIVIDUALCLUSTERS=nan;
HANDLES=[];
p=[];
p1=[];
p2=[];
A={};
HISTa=[];
HISTb=[];

[x,y,z]=ndgrid(1:VOL.dim(1),1:VOL.dim(2),1:VOL.dim(3));
XYZ=reshape([x(:),y(:),z(:),ones(numel(x),1)]*VOL.mat',size(x,1),size(x,2),size(x,3),[]);
hfig=figure;
surf_volume_update;
if DODISP, uiwait(hfig); end
if ishandle(hfig)
    p=p2;
    delete(hfig);
end
%if ~isempty(p)&&~nargout
%end

    function h=surf_volume_update(varargin)
        if numel(HANDLES)>=1, THR=str2num(get(HANDLES(1),'string')); end
        if numel(HANDLES)>=2, SMOOTH=str2num(get(HANDLES(2),'string')); end
        if numel(HANDLES)>=3, DISREGARDZEROS=get(HANDLES(3),'value'); end
        if numel(HANDLES)>=4, HEMSEPARATE=get(HANDLES(4),'value'); end
        if numel(HANDLES)>=5, INDIVIDUALCLUSTERS=get(HANDLES(5),'value'); end
        clf(hfig);
        uicontrol('style','frame','units','norm','position',[0,.83,1,.17]);
        uicontrol('style','text','units','norm','position',[.05,.90,.3,.05],'string','Intensity threshold','horizontalalignment','right');
        uicontrol('style','text','units','norm','position',[.05,.85,.3,.05],'string','Smoothing level','horizontalalignment','right');
        HANDLES(1)=uicontrol('style','edit','units','norm','position',[.36,.90,.1,.05],'string',num2str(THR),'callback',@surf_volume_update);
        HANDLES(2)=uicontrol('style','edit','units','norm','position',[.36,.85,.1,.05],'string',num2str(SMOOTH),'callback',@surf_volume_update);
        HANDLES(3)=uicontrol('style','checkbox','units','norm','position',[.55,.94,.44,.05],'string','Disregard Intensity=0 values','value',DISREGARDZEROS,'callback',@surf_volume_update);
        HANDLES(4)=uicontrol('style','checkbox','units','norm','position',[.55,.89,.44,.05],'string','Separate by hemisphere','value',HEMSEPARATE,'callback',@surf_volume_update);
        HANDLES(5)=uicontrol('style','checkbox','units','norm','position',[.55,.84,.44,.05],'string','Separate noncontiguous surfaces/clusters','value',INDIVIDUALCLUSTERS,'callback',@surf_volume_update);
        uicontrol('style','frame','units','norm','position',[0,.0,1,.15]);
        uicontrol('style','pushbutton','units','norm','position',[.65,.03,.15,.09],'string','Cancel','callback','delete(gcbf)');
        uicontrol('style','pushbutton','units','norm','position',[.80,.03,.15,.09],'string','Ok','callback','uiresume(gcbf)');
        set(hfig,'pointer','watch');
        if DODISP, drawnow; end
        try
            if ~isequal(DISREGARDZEROS,OLDDISREGARDZEROS)||~isequal(THR,OLDTHR)||~isequal(HEMSEPARATE,OLDHEMSEPARATE)||~isequal(INDIVIDUALCLUSTERS,OLDINDIVIDUALCLUSTERS)
                dat=DAT;
                if DISREGARDZEROS, dat(dat==0)=nan; end
                if HEMSEPARATE
                    p1a=isosurface(XYZ(:,:,:,1),XYZ(:,:,:,2),XYZ(:,:,:,3),dat>=THR&XYZ(:,:,:,1)<=0,.5);
                    p1b=isosurface(XYZ(:,:,:,1),XYZ(:,:,:,2),XYZ(:,:,:,3),dat>=THR&XYZ(:,:,:,1)>=0,.5);
                    p1=[p1a,p1b];
                else
                    p1=isosurface(XYZ(:,:,:,1),XYZ(:,:,:,2),XYZ(:,:,:,3),dat>=THR,.5);
                end
                if INDIVIDUALCLUSTERS
                    p1temp=repmat(struct('vertices',[],'faces',[]),1,0); p1size=[];
                    for m=1:numel(p1),
                        Atemp=double(sparse(repmat(p1(m).faces,3,1),repmat(p1(m).faces,1,3), 1)>0);
                        [p1idx,nill,p1r]=dmperm(Atemp);
                        for np1r=1:numel(p1r)-1
                            vertexcluster=p1idx(p1r(np1r):p1r(np1r+1)-1);
                            [faceclusters,newvertexcluster]=ismember(p1(m).faces,vertexcluster);
                            p1temp(end+1)=struct('vertices',p1(m).vertices(vertexcluster,:), 'faces',newvertexcluster(all(faceclusters,2),:));
                            p1size(end+1)=numel(vertexcluster);
                        end
                    end
                    [nill,p1idx]=sort(p1size,'descend');
                    p1=p1temp(p1idx(nill>=20));
                end
                for m=1:numel(p1),
                    A{m}=double(sparse(repmat(p1(m).faces,3,1),repmat(p1(m).faces,1,3), 1)>0);
                    A{m}=sparse(1:size(A{m},1),1:size(A{m},1),1./sum(A{m},2))*A{m};
                end
                [HISTa,HISTb]=hist(dat(~isnan(dat)),100);
            end
            if ~isequal(DISREGARDZEROS,OLDDISREGARDZEROS)||~isequal(THR,OLDTHR)||~isequal(SMOOTH,OLDSMOOTH)||~isequal(INDIVIDUALCLUSTERS,OLDINDIVIDUALCLUSTERS)
                p2=p1;
                for m=1:numel(p2),for n=1:SMOOTH,p2(m).vertices=A{m}*p2(m).vertices; end;end
                OLDTHR=THR;
                OLDSMOOTH=SMOOTH;
            end
            
            set(hfig,'name','surf_volume: Compute isosurface','numbertitle','off','color','k');
            h1=subplot(121);
            patch([HISTb(1),HISTb,HISTb(end)],[DOLOGHIST,HISTa,DOLOGHIST],'b');
            hold on; plot(THR*[1,1],[DOLOGHIST,max(HISTa)],'y-'); hold off
            xlabel('Intensity values');
            set(h1,'units','norm','position',[.1,.4,.35,.3],'color','k','xcolor',.5*[1 1 1],'ycolor',.5*[1 1 1],'box','off','handlevisibility','off','ylim',[DOLOGHIST,max(HISTa)]);
            if DOLOGHIST, set(h1,'yscale','log'); end
            
            h2=subplot(122);
            cmap=.5+.5*rand(numel(p2),3);
            for m=1:numel(p2),
                patch(p2(m),'edgecolor','none','facevertexcdata',repmat(cmap(m,:),size(p2(m).vertices,1),1),...
                    'facecolor','interp','alphadatamapping','none','FaceLighting', 'gouraud');
            end
            axis equal;
            view(VIEW);
            %axis tight;
            light('position',[1 0 0]);
            light('position',[-1 0 0]);
            set(h2,'units','norm','position',[.55,.25,.4,.5],'color','k','xcolor',.5*[1 1 1],'ycolor',.5*[1 1 1],'zcolor',.5*[1 1 1]);
            xlabel x; ylabel y; zlabel z;
            grid on;
            title('Isosurface','color',.5*[1 1 1]);
            set(rotate3d,'ActionPostCallback',@surf_volume_rotate,'enable','on');
            set(hfig,'pointer','arrow');
            if DODISP, drawnow; end
        catch
            disp(lasterr);
        end
    end

    function surf_volume_rotate(varargin)
        pt=get(gca,'cameraposition');
        VIEW=pt./max(eps,sqrt(sum(pt.^2)));
    end
end