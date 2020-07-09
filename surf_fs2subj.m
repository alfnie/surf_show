function surf_fs2subj(file_fs,folder_subj,fileout)
% SURF_FS2SUBJ
% projects fsaverage-space results onto subject surfaces
% surf_fs2subj(filename_fsaverage,folder_subject,filename_subject)
%   filename_fsaverage: original file in fsaverage space that you want to project
%   folder_subj:        subject folder (containing ./surf directory) 
%   filename_subject:   output file in subject space that you want to create
%
% input formats: .img .nii .rgb .paint .annot
% output formats: .paint .rgb
%

[filepath,filename,fileext]=fileparts(file_fs);
switch(fileext)
    case {'.img','.nii'}
        data_fs=spm_read_vols(spm_vol(file_fs));
        data_fs=num2cell(reshape(data_fs,[],2),1);
        side=1:2;
        prefix={'lh.','rh.'};
    case '.rgb'
        fh=fopen(file_fs,'rb');
        data_fs={double(reshape(fread(fh,inf,'uint8'),[],3))/255};
        fclose(fh);
        if strncmp(filename,'lh.',3), side=1;
        elseif strncmp(filename,'rh.',3), side=2;
        else error('unknown hemisphere for file %s',file_fs);
        end
        prefix={''};
    case '.annot'
        [temp_vert,temp_label,temp_table]=read_annotation(file_fs,0);
        [nill,temp_rois]=ismember(temp_label,temp_table.table(:,5));
        data_fs={temp_rois};
        if strncmp(filename,'lh.',3), side=1;
        elseif strncmp(filename,'rh.',3), side=2;
        else error('unknown hemisphere for file %s',file_fs);
        end
        prefix={''};
    case '.paint'
        data_fs={read_curv(file_fs)};
        if strncmp(filename,'lh.',3), side=1;
        elseif strncmp(filename,'rh.',3), side=2;
        else error('unknown hemisphere for file %s',file_fs);
        end
        prefix={''};
    otherwise
        error('file format %s not supported',fileext);
end
if size(data_fs{1},1)~=prod(surf_dims(8)), error('incorrect dimensions in file %s',file_fs); end
if ~isempty(dir(fullfile(folder_subj,'surf','lh.sphere.reg'))), folder_subj=fullfile(folder_subj,'surf'); end
if nargin<3, fileout='surf_fs2subj_output.paint'; end

if any(side==1), 
    [xyz_lh,faces_lh]=read_surf(fullfile(folder_subj,'lh.sphere.reg')); 
    [ref,sphere2xyz_lh]=surf_sphere(8,xyz_lh);
end
if any(side==2), 
    [xyz_rh,faces_rh]=read_surf(fullfile(folder_subj,'rh.sphere.reg')); 
    [ref,sphere2xyz_rh]=surf_sphere(8,xyz_rh);
end
[filepath,filename,fileext]=fileparts(file_fs);
[fileoutpath,fileoutname,fileoutext]=fileparts(fileout);
for nfile=1:numel(data_fs)
    tfileout=[prefix{nfile} fileout];
    switch(side(nfile))
        case 1,
            tdata=data_fs{nfile}(sphere2xyz_lh,:);
            nfaces=size(faces_lh,1);
        case 2,
            tdata=data_fs{nfile}(sphere2xyz_rh,:);
            nfaces=size(faces_rh,1);
    end
    switch(fileoutext)
        case '.rgb'
            fh=fopen(tfileout,'wb');
            fwrite(fh,max(0,min(255,round(tdata*255))),'uint8');
            fclose(fh);
        case '.paint'
            write_curv(tfileout, tdata, nfaces);
        otherwise
            error('output format %s not supported',fileoutext);
    end
    fprintf('Written file %s\n',tfileout);
end




