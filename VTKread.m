function p=VTKread(filename)
[file_path,file_name]=fileparts(filename);
filenames={file_name,[file_name,'.gz'],[file_name,'.img'],[file_name,'.nii']};
volinfo=[];
for n=1:numel(filenames)
    if ~isempty(dir(fullfile(file_path,filenames{n}))), volinfo=MRIread(fullfile(file_path,filenames{n})); break; end
end
if isempty(volinfo), error(['Missing anatomical file associated with vtk file ',filename]); end

t=volinfo.tkrvox2ras';
p=[];
fh=fopen(filename,'rt');
fgetl(fh);
fgetl(fh);
if ~strcmp(fgetl(fh),'ASCII'), return; end
if ~strcmp(fgetl(fh),'DATASET POLYDATA'), return; end
m=strread(fgetl(fh),'POINTS %d float');
vertices=zeros(m,3);
for n=1:m
    vertices(n,:)=sscanf(fgetl(fh),'%f');
end
[m,k]=strread(fgetl(fh),'POLYGONS %d %d');
for n=1:m
    i=sscanf(fgetl(fh),'%f');
    if n==1||i(1)~=size(p(end).faces,2), p(end+1).faces=zeros(0,i(1)); p(end).vertices=[]; end
    p(end).faces(end+1,:)=i(2:end);
end
for n=1:numel(p)
    faces=p(n).faces+1;
    [i,j,k]=unique(faces);
    p(n).vertices=[vertices(i,:),ones(numel(i),1)]*t(:,1:3);
    p(n).faces=reshape(k,size(faces));
end
fclose(fh);
end



