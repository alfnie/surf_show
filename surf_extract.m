function [data,fileout,fileout2]=surf_extract(filename,surfnames,FS_folder,smooth,DODISP,DOSAVE,DOQC)

if nargin<3, FS_folder=''; end
if nargin<4||isempty(smooth), smooth=0; end
if nargin<5||isempty(DODISP), DODISP=false; end
if nargin<6||isempty(DOSAVE), DOSAVE=~nargout; end
if nargin<7||isempty(DOQC), DOQC=false; end
if isempty(FS_folder) % extracts from single surface file (assumes all files in MNI space)
    if DODISP
        [file_path,file_name,file_ext]=fileparts(surfnames);
        if isempty(regexp([file_name,file_ext],'^lh|^rh'))||~isempty(regexp([file_name,file_ext],'subcortical|cerebellum'))||any(strcmp([file_name,file_ext],{'lh.pial.surf','rh.pial.surf'}))
            surfnames={surfnames};
        else
            surfnames={fullfile(fileparts(which(mfilename)),'surf',[file_name(1:3),'pial.surf']),surfnames};
        end
        for n1=1:numel(surfnames),[tfile_path,tfile_name,tfile_ext]=fileparts(surfnames{n1}); surfnames_redux{n1}=[tfile_name,tfile_ext]; end
        hfig=figure('units','norm','position',[.4,.5,.3,.2],'color','w','name','Extract values at surface coordinates','numbertitle','off','menubar','none');
        uicontrol('style','text','units','norm','position',[.1,.8,.8,.1],'string','Extract values at coordinates:','backgroundcolor','w','horizontalalignment','left');
        ht1=uicontrol('style','popupmenu','units','norm','position',[.1,.7,.8,.1],'string',surfnames_redux,'value',1);
        uicontrol('style','text','units','norm','position',[.1,.45,.8,.1],'string','Smoothing level:','backgroundcolor','w','horizontalalignment','left');
        ht2=uicontrol('style','edit','units','norm','position',[.1,.35,.8,.1],'string',num2str(smooth),'tooltipstring','Enter radius (number of vertices) for surface-smoothing of extracted values');
        uicontrol('style','pushbutton','string','OK','units','norm','position',[.1,.01,.38,.15],'callback','uiresume');
        uicontrol('style','pushbutton','string','Cancel','units','norm','position',[.51,.01,.38,.15],'callback','delete(gcbf)');
        uiwait(hfig);
        if ishandle(hfig)
            surfnames=surfnames{get(ht1,'value')};
            smooth=str2num(get(ht2,'string'));
            delete(hfig);
        else
            data=[];
            return;
        end
    else
        [file_path,file_name,file_ext]=fileparts(surfnames);
        if isempty(regexp([file_name,file_ext],'^lh|^rh'))||~isempty(regexp([file_name,file_ext],'subcortical|cerebellum'))||any(strcmp([file_name,file_ext],{'lh.pial.surf','rh.pial.surf'}))
            surfnames={surfnames};
        else
            surfnames={fullfile(fileparts(which(mfilename)),'surf',[file_name(1:3),'pial.surf']),fullfile(fileparts(which(mfilename)),'surf',[file_name(1:3),'white.surf'])};
        end
        %surfnames=surfnames{1};
    end
    if isstruct(filename), vol=filename;
    else  vol=spm_vol(filename);
    end
    if ~iscell(surfnames),surfnames={surfnames};end
    data={};XYZ={};
    for i=1:numel(surfnames)
        if isstruct(surfnames{i})
            xyz=surfnames{i}.vertices;
            faces=surfnames{i}.faces;
        else
            [xyz,faces]=read_surf(surfnames{i});
            faces=faces+1;
        end
        if numel(surfnames)==2
            if i==1, XYZ=xyz; continue; end
            data_ref=0;data_refn=0;
            Alpha=0:.1:1;
            for alpha=Alpha
                t=xyz*alpha+XYZ*(1-alpha);
                ijk=pinv(vol.mat)*[t,ones(size(t,1),1)]';
                tdata_ref=spm_get_data(vol,ijk);
                tdata_ref(isnan(tdata_ref))=0;
                data_ref=data_ref+tdata_ref;
                data_refn=data_refn+(tdata_ref~=0);
            end
            data_ref=data_ref./max(eps,data_refn);
        else
            %ijk=pinv(vol.mat)*a.vox2ras0*pinv(a.tkrvox2ras)*[xyz,ones(size(xyz,1),1)]';
            ijk=pinv(vol.mat)*[xyz,ones(size(xyz,1),1)]';
            data_ref=spm_get_data(vol,ijk);
        end
        XYZ=xyz;
        if 0
            ivolmat=pinv(vol.mat);
            for n1=-smooth:smooth
            for n2=-smooth:smooth
            for n3=-smooth:smooth
                ijk=ivolmat*[xyz+repmat([n1 n2 n3],size(xyz,1),1),ones(size(xyz,1),1)]';
                data_ref=max(data_ref,spm_get_data(vol,ijk));
            end
            end
            end
        end
        data_ref=data_ref(:);
        if smooth>0
            data_ref(isnan(data_ref))=0;
            A=double(sparse(repmat(faces,3,1),repmat(faces,1,3), 1)>0);
            A=double(A|speye(size(A,1)));
            %A=sparse(1:size(A,1),1:size(A,1),1./sum(A,2))*A;
            A=A*sparse(1:size(A,1),1:size(A,1),1./sum(A,2));
            for n=1:smooth,
                data_ref=A*data_ref; 
            end
        end
        data{i}=data_ref;
    end
    if numel(data)<=2, data=data{find(cellfun('length',data)>0,1)}; end
    
else % extracts from arbitrary freesurfer surfaces (subject-specific coordinates)
    names={'brain.mgh','T1.mgh','brain.mgz','T1.mgz'};
    valid=cellfun(@(name)~isempty(dir(fullfile(FS_folder,'mri',name))),names);
    if ~any(valid), 
        if ~nargout, error('missing anatomical data'); 
        else
            disp('missing anatomical data'); data=[]; fileout=''; return;
        end
    end
    for inames=find(valid)
        try
            a=MRIread(fullfile(FS_folder,'mri',names{inames}),true);
            break;
        end
    end
        
    alpha=.05:.1:.95;
    if DOQC, alpha=[alpha alpha+1 alpha-1]; end
    if nargin<2||isempty(surfnames), surfnames={'.white','.pial','.sphere.reg'}; end
    resolution=8;
    hems={'lh','rh'};
    [file_path,file_name,file_ext,file_num]=spm_fileparts(filename);
    
    vol=spm_vol(filename);
    data=[];
    dataraw=[];
    datarawA=[]; datarawB=[]; ijk0=[];ijk0A=[];ijk0B=[];
    alpha=permute(alpha(:),[2,3,1]);
    for hem=1:2,
        shem=hems{hem};
        [xyz1,faces]=read_surf(fullfile(FS_folder,'surf',[shem,surfnames{1}]));
        faces=faces+1;
        if numel(surfnames)>=2&&~isempty(surfnames{2})
            xyz2=read_surf(fullfile(FS_folder,'surf',[shem,surfnames{2}]));
            xyz_data=bsxfun(@times,alpha,xyz1')+bsxfun(@times,1-alpha,xyz2');
        else
            xyz_data=xyz1';
        end
        ijk=pinv(vol.mat)*a.vox2ras0*pinv(a.tkrvox2ras)*[xyz_data(:,:);ones(1,size(xyz_data,2)*size(xyz_data,3))];
        data_ref=spm_get_data(vol,ijk);
        data_refA=[];
        if numel(alpha)>1
%             % mean ignoring nan's
%             data_ref=reshape(data_ref,[size(xyz_data,2),size(xyz_data,3)])';
%             idata_ref=isnan(data_ref);
%             data_ref(idata_ref)=0;
%             data_ref=sum(data_ref,1)./max(eps,sum(~idata_ref,1));
            if DOQC
                data_ref=sort(reshape(data_ref,[size(xyz_data,2),size(xyz_data,3)/3,3]),2);
                idata_ref=max(1,ceil(sum(~isnan(data_ref),2)/2));
                data_refA=data_ref((1:size(data_ref,1))'+size(data_ref,1)*(idata_ref(:,:,2)-1)+1*size(data_ref,1)*size(data_ref,2))';
                data_refB=data_ref((1:size(data_ref,1))'+size(data_ref,1)*(idata_ref(:,:,2)-1)+2*size(data_ref,1)*size(data_ref,2))';
                data_ref=data_ref((1:size(data_ref,1))'+size(data_ref,1)*(idata_ref(:,:,1)-1))';
                ijk=round(reshape(ijk,[size(ijk,1),size(ijk,2)/3,3]));
            else
                % median ignoring nan's
                data_ref=sort(reshape(data_ref,[size(xyz_data,2),size(xyz_data,3)]),2);
                idata_ref=max(1,ceil(sum(~isnan(data_ref),2)/2));
                data_ref=data_ref((1:size(data_ref,1))'+size(data_ref,1)*(idata_ref-1))';
            end
        end
        if numel(surfnames)>=3&&~isempty(surfnames{3}) % resample at sphere reference grid
            xyz_ref=read_surf(fullfile(FS_folder,'surf',[shem,surfnames{3}]));
            [xyz_sphere,sphere2ref,ref2sphere]=surf_sphere(resolution,xyz_ref);
            data_ref=data_ref(:,ref2sphere);
            if DOQC&&~isempty(data_refA)
                data_refA=data_refA(:,ref2sphere);
                data_refB=data_refB(:,ref2sphere);
            end
            faces=xyz_sphere.faces;
        end
        dataraw_ref=data_ref;
        if DOQC&&~isempty(data_refA)
            dataraw_refA=data_refA;
            dataraw_refB=data_refB;
        end
        if smooth>0 % smooths on surface
            data_ref(isnan(data_ref))=0;
            A=double(sparse(repmat(faces,3,1),repmat(faces,1,3), 1)>0);
            A=double(A|speye(size(A,1)));
            A=A*sparse(1:size(A,1),1:size(A,1),1./sum(A,2));
            for n=1:smooth,
                data_ref=data_ref*A'; 
            end
        end
        if numel(surfnames)>=3&&~isempty(surfnames{3})&&DOSAVE
            dim=surf_dims(resolution);
            newvol=struct('fname',fullfile(file_path,[file_name,'.',shem,'.surf',num2str(resolution),'.smooth',num2str(smooth),'.img',file_num]),...
                'mat',eye(4),...
                'dim',dim,...
                'pinfo',[1;0;0],...
                'dt',[spm_type('float32'),spm_platform('bigend')],...
                'descrip','surface data');
            if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
            spm_write_vol(newvol,reshape(data_ref,dim));
            disp(['Created file ',newvol.fname]);
            if smooth>0
                newvol=struct('fname',fullfile(file_path,[file_name,'.',shem,'.surf',num2str(resolution),'.smooth',num2str(0),'.img',file_num]),...
                    'mat',eye(4),...
                    'dim',dim,...
                    'pinfo',[1;0;0],...
                    'dt',[spm_type('float32'),spm_platform('bigend')],...
                    'descrip','surface data');
                if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
                spm_write_vol(newvol,reshape(dataraw_ref,dim));
                disp(['Created file ',newvol.fname]);
            end
        end
        data=[data,data_ref];
        dataraw=[dataraw,dataraw_ref];
        if DOQC&&~isempty(data_refA)
            datarawA=[datarawA,dataraw_refA];
            datarawB=[datarawB,dataraw_refB];
            ijk0=[ijk0 ijk(:,:,1)];
            ijk0A=[ijk0A ijk(:,:,2)];
            ijk0B=[ijk0B ijk(:,:,3)];
        end        
    end
    if numel(surfnames)>=3&&~isempty(surfnames{3})&&DOSAVE
        dim=surf_dims(resolution);
        dim=dim.*[1 1 2];
        newvol=struct('fname',fullfile(file_path,[file_name,'.surf',num2str(resolution),'.smooth',num2str(smooth),'.img',file_num]),...
            'mat',eye(4),...
            'dim',dim,...
            'pinfo',[1;0;0],...
            'dt',[spm_type('float32'),spm_platform('bigend')],...
            'descrip','surface data');
        if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
        spm_write_vol(newvol,reshape(data,dim));
        disp(['Created file ',newvol.fname]);
        fileout=newvol.fname;
        if smooth>0
            newvol=struct('fname',fullfile(file_path,[file_name,'.surf',num2str(resolution),'.smooth',num2str(0),'.img',file_num]),...
                'mat',eye(4),...
                'dim',dim,...
                'pinfo',[1;0;0],...
                'dt',[spm_type('float32'),spm_platform('bigend')],...
                'descrip','surface data');
            if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
            spm_write_vol(newvol,reshape(dataraw,dim));
            disp(['Created file ',newvol.fname]);
        end
        if DOQC&&~isempty(data_refA) % surface files with white/pial data for comparison/QC
            newvol=struct('fname',fullfile(file_path,[file_name,'.surf',num2str(resolution),'.smooth',num2str(0),'.QC',surfnames{1},'.img',file_num]),...
                'mat',eye(4),...
                'dim',dim,...
                'pinfo',[1;0;0],...
                'dt',[spm_type('float32'),spm_platform('bigend')],...
                'descrip','surface data');
            if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
            spm_write_vol(newvol,reshape(datarawA,dim));
            disp(['Created file ',newvol.fname]);
            newvol=struct('fname',fullfile(file_path,[file_name,'.surf',num2str(resolution),'.smooth',num2str(0),'.QC',surfnames{2},'.img',file_num]),...
                'mat',eye(4),...
                'dim',dim,...
                'pinfo',[1;0;0],...
                'dt',[spm_type('float32'),spm_platform('bigend')],...
                'descrip','surface data');
            if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
            spm_write_vol(newvol,reshape(datarawB,dim));
            disp(['Created file ',newvol.fname]);
            if DOQC>1 % volume files with gray/white/pial masks
                newvol=struct('fname',fullfile(file_path,[file_name,'.QC.img',file_num]),...
                    'mat',vol.mat,...
                    'dim',vol.dim,...
                    'pinfo',[1;0;0],...
                    'dt',[spm_type('float32'),spm_platform('bigend')],...
                    'descrip','surface mask');
                if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
                ijk0valid=ijk0(1,:)>=1&ijk0(1,:)<=vol.dim(1)& ijk0(2,:)>=1&ijk0(2,:)<=vol.dim(2)& ijk0(3,:)>=1&ijk0(3,:)<=vol.dim(3);
                temp=accumarray(ijk0(1:3,ijk0valid)',1,vol.dim);
                spm_write_vol(newvol,temp);
                disp(['Created file ',newvol.fname]);
                newvol=struct('fname',fullfile(file_path,[file_name,'.QC',surfnames{1},'.img',file_num]),...
                    'mat',vol.mat,...
                    'dim',vol.dim,...
                    'pinfo',[1;0;0],...
                    'dt',[spm_type('float32'),spm_platform('bigend')],...
                    'descrip','surface mask');
                if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
                ijk0valid=ijk0A(1,:)>=1&ijk0A(1,:)<=vol.dim(1)& ijk0A(2,:)>=1&ijk0A(2,:)<=vol.dim(2)& ijk0A(3,:)>=1&ijk0A(3,:)<=vol.dim(3);
                temp=accumarray(ijk0A(1:3,ijk0valid)',1,vol.dim);
                spm_write_vol(newvol,temp);
                disp(['Created file ',newvol.fname]);
                newvol=struct('fname',fullfile(file_path,[file_name,'.QC',surfnames{2},'.img',file_num]),...
                    'mat',vol.mat,...
                    'dim',vol.dim,...
                    'pinfo',[1;0;0],...
                    'dt',[spm_type('float32'),spm_platform('bigend')],...
                    'descrip','surface mask');
                if ~isempty(dir(newvol.fname)), try, [ok,nill]=system(sprintf('rm -f ''%s''',newvol.fname)); [ok,nill]=system(sprintf('rm -f ''%s''',regexprep(newvol.fname,'\.img(,\d+)?$','.hdr'))); end; end
                ijk0valid=ijk0B(1,:)>=1&ijk0B(1,:)<=vol.dim(1)& ijk0B(2,:)>=1&ijk0B(2,:)<=vol.dim(2)& ijk0B(3,:)>=1&ijk0B(3,:)<=vol.dim(3);
                temp=accumarray(ijk0B(1:3,ijk0valid)',1,vol.dim);
                spm_write_vol(newvol,temp);
                disp(['Created file ',newvol.fname]);
            end
        end
        fileout2=newvol.fname;
    end
end
end

