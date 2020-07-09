function surf_annot2rgb(varargin)
% SURF_ANNOT2RGB filename.annot
% converts freesurfer filename.annot file into:
%   lh|rh.filename.border.paint (ROI boundaries -e.g. used in surf_show)
%   lh|rh.filename.rgb          (ROI colors -e.g. used in surf_show)
%   filename.nii/filename.txt   (surface nifti ROI files -e.g. used in db_search/conn)

if nargin==1&&ischar(varargin{1}), roifiles=varargin;
elseif nargin==1&&iscell(varargin{1}), roifiles=varargin{1};
else roifiles=varargin;
end

log=struct('name',{{}},'hem',[],'data',{{}},'labels',{{}});
for nfile=1:numel(roifiles)
    % gets info from .annot file
    roifile=roifiles{nfile};
    [temp_vert,temp_label,temp_table]=read_annotation(roifile,0);
    [nill,temp_rois]=ismember(temp_label,temp_table.table(:,5));
    temp_colors=temp_table.table(:,1:3)/255;
    names_rois=temp_table.struct_names;
    
    if strcmp(roifile(1:2),'lh'), lhrh=1; filename='lh.pial.surf';
    elseif strcmp(roifile(1:2),'rh'), lhrh=2; filename='rh.pial.surf';
    else error;
    end

    % gets vertex position / adjacency
    [xyz,faces]=read_surf(filename);
    A=spm_mesh_adjacency(faces+1);

    % computes ROI borders
    border=zeros(size(temp_rois));
    for n1=1:numel(border), border(n1)=temp_rois(n1)>min(temp_rois(A(:,n1)>0)); end

    % writes .border.paint file
    [file_path,file_name,file_ext]=fileparts(roifile);
    write_curv([file_name,'.border.paint'],border,size(faces,1));
    fprintf('Created file %s\n',[file_name,'.border.paint']);
    
    % writes .border.paint file
    fh=fopen([file_name,'.rgb'],'wb');
    fwrite(fh,round(temp_colors(temp_rois,:)*255),'uint8');
    fclose(fh);
    fprintf('Created file %s\n',[file_name,'.rgb']);
    
    log.name{end+1}=file_name(4:end);
    log.hem(end+1)=lhrh;
    log.data{end+1}=temp_rois;
    log.labels{end+1}=names_rois;
end

% creates associated .nii / .txt files
for nfile1=1:numel(log.name)
    for nfile2=nfile1+1:numel(log.name)
        if strcmp(log.name{nfile1},log.name{nfile2})&&isequal(sort(log.hem([nfile1 nfile2])),[1 2])
            ifile=[nfile1,nfile2];
            fname=[log.name{ifile(1)},'.surf.img'];
            [nill,idx]=sort(log.hem(ifile));
            ifile=ifile(idx);
            %dim=surf_dims(8).*[1 1 2];
            dim=conn_surf_dims(8).*[1 1 2];
            data=[log.data{ifile(1)}(:) log.data{ifile(2)}(:)];
            if numel(data)==prod(dim)
                names_rois=log.labels{ifile(1)};
                none=find(strncmp('None',names_rois,4));
                data(ismember(data,none))=0;
                data(data(:,2)>0,2)=numel(names_rois)+data(data(:,2)>0,2);
                names_rois=[cellfun(@(x)[x ' (L)'],names_rois,'uni',0); cellfun(@(x)[x ' (R)'],names_rois,'uni',0)];
                V=struct('mat',eye(4),'dim',dim,'pinfo',[1;0;0],'fname',fname,'dt',[spm_type('uint16') spm_platform('bigend')]);
                spm_write_vol(V,reshape(data,dim));
                fprintf('Created file %s\n',fname);
                fname=[log.name{ifile(1)},'.surf.txt'];
                fh=fopen(fname,'wt');
                for n=1:max(data(:))
                    fprintf(fh,'%s\n',names_rois{n});
                end
                fclose(fh);
                fprintf('Created file %s\n',fname);
            end
        end
    end
end