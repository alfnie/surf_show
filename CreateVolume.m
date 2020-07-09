function patches=CreateVolume(brainVolFN, coordFN, outputVolFN, varargin)
%% Config
DEFAULT_SHAPE = 's';
DEFAULT_SIZE = 5;
DEFAULT_VAL = 1; 
CROSSHAIR_THICKNESS = 3;

%% Check dependencies
rpath = which('MRIread');
if isempty(rpath)
    error('Cannot find path to required program: MRIread');
end

rpath = which('MRIwrite');
if isempty(rpath)
    error('Cannot find path to required program: MRIwrite');
end

%% Check input arguments
if nargin <  3
    fprintf(1, 'USAGE: CreateVolume(brainVolFN, coordFN, outputVolFN);\n');
    fprintf(1, '       CreateVolume(brainVolFN, coordFN, outputVolFN, shape);\n');
    fprintf(1, '       CreateVolume(brainVolFN, coordFN, outputVolFN, shape, size);\n');
    fprintf(1, '\nNOTE: In the 2nd and 3rd usage, the shape and/or size will be overridden\n');
    fprintf(1, '        by entries in the coodinates file.\n');
    fprintf(1, '\nshape:\n');
    fprintf(1, '    s - sphere (size --> side length, in mm)\n');
    fprintf(1, '    c - crosshair in MNI space (size --> length of each axis, in mm\n');
    fprintf(1, '    r - crosshair in image space (size --> length of each axis, in voxels\n');
    fprintf(1, '    u - cube in MNI space (size --> diameter, in mm)\n');
    fprintf(1, '    b - cube in image space (size --> diameter, in voxels)\n');
    return
end

if nargin > 3
    DEFAULT_SHAPE = varargin{1};
    
    if nargin > 4
        DEFAULT_SIZE = varargin{2};
    end
end

%% Read coordinates file
if isequal(coordFN(end - 3 : end), '.txt')
    crdInfo = readCoordsFile(coordFN, DEFAULT_SHAPE, DEFAULT_SIZE, DEFAULT_VAL);
elseif isequal(coordFN(end - 3 : end), '.xls')
    crdInfo = readCoordsFile_xls(coordFN, DEFAULT_SHAPE, DEFAULT_SIZE, DEFAULT_VAL);
else
    error('Unrecognized file extension name: %s', coordFN(end - 3 : end));
end


assert(size(crdInfo.crd, 1) == length(crdInfo.val));
assert(size(crdInfo.crd, 1) == length(crdInfo.shape));
assert(size(crdInfo.crd, 1) == length(crdInfo.size));

if size(crdInfo.crd, 1) == 0
    error('Coordinate file %s contains no points', coordFN);
end

%% Read brain volume
if isempty(brainVolFN), imb=[];
else imb = MRIread(brainVolFN);
end

%% Create patches
for i1 = 1 : length(crdInfo.val)
    t_mni = crdInfo.crd(i1, :);
    siz = crdInfo.size(i1);
    patches(i1)=VTKloadref(crdInfo.shape{i1},t_mni,siz,imb);
end
if nargout>0, return; end

%% Filling volumes
imc = imb;
imc.vol(:) = 0;
[ix,iy,iz]=ndgrid(1:imb.volsize(1),1:imb.volsize(2),1:imb.volsize(3));
xyz_vox=[ix(:),iy(:),iz(:)];
xyz_mni=vox2mni(xyz_vox,imb);

for i1 = 1 : length(crdInfo.val)
    t_mni = crdInfo.crd(i1, :);
    t_vox = round(mni2vox(t_mni,imb));
    siz = crdInfo.size(i1);
    
    if isequal(crdInfo.shape{i1}, 'u') % -- Cube -- (MNI space)%
        distance_mm=abs(bsxfun(@minus,xyz_mni,t_mni));
        mask = all(distance_mm<=siz/2,2);
    elseif isequal(crdInfo.shape{i1}, 'b') % -- Cube -- (image space)%
        distance_vox = abs(bsxfun(@minus,xyz_vox,t_vox));
        mask = all(distance_vox<=(siz-1)/2,2);
    elseif isequal(crdInfo.shape{i1}, 'c') % -- 3D crosshair -- (MNI space)%
        distance_mm=abs(bsxfun(@minus,xyz_mni,t_mni));
        distance_vox = abs(bsxfun(@minus,xyz_vox,t_vox));
        mask = sum(distance_mm.^2,2)<=(siz/2)^2 & sum(distance_vox<=(CROSSHAIR_THICKNESS-1)/2,2)>=2;
    elseif isequal(crdInfo.shape{i1}, 'r') % -- 3D crosshair -- (image space)%
        distance_vox = abs(bsxfun(@minus,xyz_vox,t_vox));
        mask = sum(distance_vox.^2,2)<=(siz/2)^2 & sum(distance_vox<=(CROSSHAIR_THICKNESS-1)/2,2)>=2;
    elseif isequal(crdInfo.shape{i1}, 's') % -- Shere -- % (MNI space)
        distance_mm=abs(bsxfun(@minus,xyz_mni,t_mni));
        mask = sum(distance_mm.^2,2)<=(siz/2)^2;
    elseif isequal(crdInfo.shape{i1}, 'p') % -- Shere -- % (image space)
        distance_vox = abs(bsxfun(@minus,xyz_vox,t_vox));
        mask = sum(distance_vox.^2,2)<=(siz/2)^2;
    else
        mask = false(imb.volsize);
    end
    imv.vol(t_vox(1),t_vox(2),t_vox(3))=crdInfo.val(i1); % makes sure at least one voxel fits the criteria (e.g. if 'siz' is too small)
    imc.vol(mask) = crdInfo.val(i1);
end

%% Write to output volume file
if exist(outputVolFN,'file') == 2
    delete(outputVolFN);
end
MRIwrite(imc, outputVolFN);
[file_path,file_name]=fileparts(outputVolFN);
VTKwrite(fullfile(file_path,[file_name,'.vtk']),patches);

return

%% Sub-routines
function mniCoord = vox2mni(coord,file)
assert(size(coord,2) == 3);
coord = coord(:,[2,1,3])-1;     % (row-major 1-based Matlab convention) to (col-major 0-based FreeSurfer convention)
mniCoord = [coord,ones(size(coord,1),1)]*file.vox2ras(1:3,:)';  % voxels to MNI
return

function coord = mni2vox(mniCoord,file)
assert(size(mniCoord,2) == 3);
coord = [mniCoord,ones(size(mniCoord,1),1)]*pinv(file.vox2ras)';  % MNI to voxels
coord = coord(:,[2,1,3])+1;     % (col-major 0-based FreeSurfer convention) to (row-major 1-based Matlab convention)
return

%%
function crdInfo = readCoordsFile(coordFN, defShape, defSize, defVal)
crdInfo = struct();
crdInfo.crd = nan(0, 3);
crdInfo.val = [];
crdInfo.shape = {};
crdInfo.size = [];

ctxt = textread(coordFN, '%s', 'delimiter', '\n');
isTalairach=false;

for i1 = 1 : numel(ctxt)
    cline = strtrim(ctxt{i1});
    cline0 = cline;
    
    c_items=regexp(cline,'[#%]','split');
    cline = strtrim(c_items{1});
    
    if isempty(cline)
        continue;
    end
    
    if numel(cline)>1&&strcmp(cline(1:2),'//')
        cline=lower(regexprep(cline,'\s+',''));
        if ~isempty(strfind(cline,'reference=talairach'))
            fprintf('Using talairach coordinates\n');
            isTalairach=true;
        elseif ~isempty(strfind(cline,'reference=mni'))
            fprintf('Using MNI coordinates\n');
            isTalairach=false;
        else
            fprintf('Warning: unrecognized comment line %s. Disregarding.\n',cline);
        end
        continue;
    end
    
    cline = strrep(cline, ',', ' ');
    c_items=regexp(cline,'\s+','split'); % note: allows tabs or multipe spaces to separate two elements
    %c_items = splitstring(cline, ' ');
    
    if numel(c_items) < 3 || numel(c_items) > 6
        error('Unrecognized format in coordinates file line "%s"', cline0);
    end
    
    t_coord = [str2double(deblank(c_items{1})), ...
        str2double(deblank(c_items{2})), ...
        str2double(deblank(c_items{3}))];

    if isTalairach
        t_coord=tal2icbm_other(t_coord);
    end
    
    if numel(c_items)>=4, t_val = str2double(deblank(c_items{4})); else t_val=defVal; end
    if numel(c_items)>=5, t_shape = strrep(strrep(deblank(c_items{5}), ' ', ''),  '\t', ''); else t_shape=defShape; end
    if numel(c_items)>=6, t_size = str2double(deblank(c_items{6})); else t_size=defSize; end
    
    if t_val == 0
        fprintf(1, 'WARNING: value == 0 for coordinate [%.1f, %.1f, %.1f]', ...
            t_coord(1), t_coord(2), t_coord(3));
    end
    
%     if numel(c_items) > 4
%         t_shape = strrep(strrep(deblank(c_items{5}), ' ', ''),  '\t', '');
%         
%         if numel(c_items) > 5
%             t_size = str2double(deblank(c_items{6}));
%         else
%             t_size = defSize;
%         end
%     else
%         t_shape = defShape;
%         t_size = defSize;
%     end
    
    crdInfo.crd = [crdInfo.crd; t_coord];
    crdInfo.val(end + 1) = t_val;
    crdInfo.shape{end + 1} = t_shape;
    crdInfo.size(end + 1) = t_size;
end
return

%%
function crdInfo = readCoordsFile_xls(coordFN, defShape, defSize, defVal)
crdInfo = struct();
crdInfo.crd = nan(0, 3);
crdInfo.val = [];
crdInfo.shape = {};
crdInfo.size = [];

[N, T] = xlsread(coordFN);
isTalairach=false;

for i1 = 1 : size(N, 1)
    if i1 <= size(T, 1);
        tline = T(i1, :);
    else
        tline = {};
    end
    
    if ~isempty(tline)&&~isempty(tline{1})&&~isempty(strfind(tline{1},'//'))
        cline=lower(regexprep(tline{1},'\s+',''));
        if ~isempty(strfind(cline,'reference=talairach'))
            fprintf('Using talairach coordinates\n');
            isTalairach=true;
        elseif ~isempty(strfind(cline,'reference=mni'))
            fprintf('Using MNI coordinates\n');
            isTalairach=false;
        else
            fprintf('Warning: unrecognized comment line %s. Disregarding this line.\n',tline{1});
        end
        continue;
    end
    if ~i1, continue; end
    
    nline = N(i1, :);
    t_coord = [nline(1), nline(2), nline(3)];
    if any(isnan(t_coord)), continue; end
    
    if isTalairach
        t_coord=tal2icbm_other(t_coord);
    end
    
    if numel(nline)<4, t_val=defVal;
    else t_val = nline(4);
    end
    
    if t_val == 0
        fprintf(1, 'WARNING: value == 0 for coordinate [%.1f, %.1f, %.1f]', ...
            t_coord(1), t_coord(2), t_coord(3));
    end
    
    if numel(tline) > 4
        t_shape = tline{5};
        
        if numel(nline) > 5 && ~isnan(nline(6))
            t_size = nline(6);
        else
            t_size = defSize;
        end
    else
        t_shape = defShape;
        t_size = defSize;
    end
    
    crdInfo.crd = [crdInfo.crd; t_coord];
    crdInfo.val(end + 1) = t_val;
    crdInfo.shape{end + 1} = t_shape;
    crdInfo.size(end + 1) = t_size;
end
return

function p=VTKloadref(shape,x,siz,volinfo)
ismni=any(strcmp(shape,{'s','c','u'}));%|~isempty(strfind(shape,'_mni'));
if any(strcmp(shape,{'s','p'})),    shape='sphere';
elseif any(strcmp(shape,{'c','r'})),shape='crosshair'; 
elseif any(strcmp(shape,{'u','b'})),shape='cube'; 
end
%shape=regexp(shape,'^[^_]*','match');
refsurfs=load(fullfile(fileparts(which(mfilename)),'VTK_ReferenceShapes.mat'));
i=strmatch(shape,refsurfs.shapes,'exact'); % finds reference patch data
assert(~isempty(i), 'unrecognized shape %s',shape);
p=refsurfs.patches{i};
if isempty(volinfo)
    if ~ismni, warning('option for voxel-oriented symbols is not available without reference file. Using MNI-orientation instead'); end
    p.vertices=bsxfun(@plus,x,p.vertices*siz/2);
else
    mm2img=pinv(volinfo.tkrvox2ras)';
    if ismni, p.vertices=[bsxfun(@plus,x,p.vertices*siz/2),ones(size(p.vertices,1),1)]*mm2img(:,1:3); % scales&orients to image space
    else      p.vertices=bsxfun(@plus, [x,1]*mm2img(:,1:3), p.vertices*siz/2);
    end
end
return

function VTKwrite(filename,p)
fh=fopen(filename,'wt');
fprintf(fh,'# vtk DataFile Version 3.0\nFile generated by CreateVolume.m\nASCII\n');
fprintf(fh,'DATASET POLYDATA\n');
n=arrayfun(@(x)size(x.vertices,1),p);
[m,k]=arrayfun(@(x)size(x.faces),p);
fprintf(fh,'POINTS %d float\n',sum(n));
for i=1:numel(p)
    fprintf(fh,'%f %f %f\n',p(i).vertices');
end
fprintf(fh,'POLYGONS %d %d\n',sum(m),sum(m.*(k+1)));
for i=1:numel(p)
    fprintf(fh,[num2str(k(i)),repmat(' %d',[1,k(i)]),'\n'],sum(n(1:i-1))+p(i).faces'-1);
end
fclose(fh);
return

