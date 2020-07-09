
filename='lh.pial';
niter=250;

[xyz,faces]=read_surf(filename);
A=spm_mesh_adjacency(faces+1);A=speye(size(A,1))|A;A=sparse(1:size(A,1),1:size(A,1),1./sum(A,2))*A;
xyz2=xyz;
for n=1:niter,xyz2=A*xyz2;end
x=[xyz2,ones(size(xyz2,1),1)];
b=pinv(x'*x)*(x'*xyz);
xyz3=x*b;
write_surf([filename,'.smoothed'],xyz3,faces);
